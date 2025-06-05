from flask import Flask, request, jsonify
import os
import json
import torch
import tarfile
import tempfile
import shutil
from transformers import T5Tokenizer, T5ForConditionalGeneration
import google.generativeai as genai
from dotenv import load_dotenv
from flask_cors import CORS
from difflib import SequenceMatcher
import database
from database import get_all_therapists

# Load environment variables (for API keys)
load_dotenv()

app = Flask(__name__)
# Allow all origins with all methods and headers
CORS(app, resources={r"/*": {"origins": "*", "methods": ["GET", "POST", "OPTIONS"], "allow_headers": "*"}})

# Configure Gemini API
genai.configure(api_key=os.environ.get("GEMINI_API_KEY"))

# Try to get available models first
try:
    available_models = genai.list_models()
    models = [model.name for model in available_models]

    print(f"Available Gemini modls for use: {models}")
    
    # Try to find the best matching model for text generation
    preferred_models = ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-pro"]
    
    selected_model = None
    for model_name in preferred_models:
        if any(model_name in model for model in models):
            for model in models:
                if model_name in model:
                    selected_model = model
                    break
            if selected_model:
                break
    
    if not selected_model and models:
        # Fallback to the first available model
        selected_model = models[0]
        
    if selected_model:
        print(f"Using Gemini model: {selected_model}")
        gemini_model = genai.GenerativeModel(selected_model)
    else:
        print("No suitable Gemini models found, refinement will be skipped")
        gemini_model = None
except Exception as e:
    print(f"Error listing Gemini models: {e}")
    gemini_model = None

# Store recent responses to avoid repetition
recent_responses = []

def is_repetitive(response, threshold=0.6):
    """Check if response is too similar to recent ones using fuzzy matching."""
    for prev in recent_responses:
        similarity = SequenceMatcher(None, response.lower(), prev.lower()).ratio()
        if similarity > threshold:
            return True
    return False

# Load your mental health model
def load_model():
    # Use a permanent directory inside your backend folder
    model_path = os.path.join(os.path.dirname(__file__), "models", "taz_model.tar")
    extracted_dir = os.path.join(os.path.dirname(__file__), "models", "extracted_model")
    model_dir = os.path.join(extracted_dir, "taz_model")
    
    # Check if extraction is needed
    if os.path.exists(model_dir) and os.path.isdir(model_dir):
        print(f"Model already extracted at {model_dir}, skipping extraction")
        
        # Verify if the extracted model has the necessary files
        if (os.path.exists(os.path.join(model_dir, "pytorch_model.bin")) or
            os.path.exists(os.path.join(model_dir, "config.json"))):
            print("Found extracted model files, proceeding to load model")
        else:
            print("Extracted model directory exists but files are missing, will re-extract")
            # If files are missing, force re-extraction
            try:
                shutil.rmtree(extracted_dir)
                os.makedirs(extracted_dir, exist_ok=True)
            except Exception as e:
                print(f"Error cleaning extraction directory: {e}")
                return None
    else:
        # Check if the model file exists
        if not os.path.exists(model_path):
            print(f"Model file not found at: {model_path}")
            return None
        
        # Create extraction directory if it doesn't exist
        os.makedirs(extracted_dir, exist_ok=True)
    
        try:
            print(f"Extracting model from {model_path} to {extracted_dir}")
            # For Windows, use a safer extraction method
            if os.name == 'nt':  # Check if running on Windows
                print("Using Windows-safe extraction method")
                with tarfile.open(model_path, "r") as tar:
                    for member in tar.getmembers():
                        try:
                            # Create directories safely
                            target_path = os.path.join(extracted_dir, member.name)
                            target_dir = os.path.dirname(target_path)
                            
                            if not os.path.exists(target_dir):
                                os.makedirs(target_dir, exist_ok=True)
                                
                            # Skip if it's a directory
                            if member.isdir():
                                continue
                                
                            # Extract files safely
                            try:
                                f = tar.extractfile(member)
                                if f is not None:
                                    with open(target_path, 'wb') as out_file:
                                        out_file.write(f.read())
                            except OSError as e:
                                print(f"Error extracting file {member.name}: {e}")
                                # Skip this file and continue with others
                                continue
                        except Exception as e:
                            print(f"Error processing {member.name}: {e}")
                            continue
            else:
                # Non-Windows extraction
                with tarfile.open(model_path, "r") as tar:
                    tar.extractall(path=extracted_dir)
                
            print(f"Model extraction completed")
        except Exception as e:
            print(f"Error extracting model: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    try:
        # Check common locations for the model files
        possible_model_dirs = [
            model_dir,  # taz_model inside extracted_model
            os.path.join(extracted_dir, "taz_model_saved"),
            extracted_dir,  # The extracted dir itself
            os.path.join(extracted_dir, "model"),
            os.path.join(extracted_dir, "chatbot_model")
        ]
        
        valid_model_dir = None
        for dir_path in possible_model_dirs:
            if os.path.exists(dir_path) and os.path.isdir(dir_path):
                # Check if this directory contains model files
                if (os.path.exists(os.path.join(dir_path, "pytorch_model.bin")) or
                    os.path.exists(os.path.join(dir_path, "config.json"))):
                    valid_model_dir = dir_path
                    print(f"Found model files in: {valid_model_dir}")
                    break
        
        if valid_model_dir is None:
            print("Could not find valid model directory in extracted contents")
            return None
        
        # Load tokenizer and model
        print(f"Loading model from {valid_model_dir}")
        tokenizer = T5Tokenizer.from_pretrained(valid_model_dir, legacy=False)
        model = T5ForConditionalGeneration.from_pretrained(valid_model_dir)
        
        # Move model to GPU if available
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"Using device: {device}")
        model = model.to(device)
        model.eval()  # Set model to evaluation mode
        
        return {
            "model": model,
            "tokenizer": tokenizer,
            "device": device,
        }
    except Exception as e:
        print(f"Error loading model: {e}")
        import traceback
        traceback.print_exc()
        return None

# Alternative way to load model if the tar approach fails
def load_model_direct():
    try:
        print("Attempting to load model directly using the pre-trained model ID")
        tokenizer = T5Tokenizer.from_pretrained("t5-small", legacy=False)
        model = T5ForConditionalGeneration.from_pretrained("t5-small")
        
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        model = model.to(device)
        model.eval()  # Set model to evaluation mode
        
        return {
            "model": model,
            "tokenizer": tokenizer,
            "device": device,
        }
    except Exception as e:
        print(f"Error loading model directly: {e}")
        return None

# Try to load from tar file first, fall back to direct loading
model_data = load_model()
if model_data is None:
    print("Falling back to direct model loading...")
    model_data = load_model_direct()

@app.route('/chat', methods=['POST'])
def chat():
    data = request.json
    user_message = data.get('message', '')
    user_emotion = data.get('emotion', 'Neutral')
    
    # Analyze mood with Gemini for a more nuanced understanding
    gemini_detected_mood = analyze_mood_with_gemini(user_message)
    
    # Use Gemini's mood if available, otherwise fall back to user's reported mood
    effective_emotion = gemini_detected_mood or user_emotion
    
    # Check for crisis indicators first
    is_crisis, crisis_type, crisis_score = detect_crisis(user_message)
    
    # Step 1: Generate initial response from your trained model
    initial_response = generate_model_response(user_message, effective_emotion)
    
    # Step 2: Refine the response with Gemini
    refined_response = refine_with_gemini(user_message, initial_response, effective_emotion)
    
    response_data = {
        'response': refined_response,
        'detected_mood': gemini_detected_mood
    }
    
    # Add crisis information if detected
    if is_crisis:
        print(f"Crisis detected: {crisis_type} with confidence {crisis_score}")
        crisis_resources = get_crisis_resources(crisis_type)
        
        response_data.update({
            'crisis_detected': True,
            'crisis_type': crisis_type,
            'crisis_score': crisis_score,
            'crisis_resources': crisis_resources
        })
        
        # For high confidence crisis, prioritize immediate help
        if crisis_score > 0.8:
            response_data['response'] = f"I notice you may be going through something serious. Please consider these resources for immediate help:\n\n{crisis_resources}\n\nRegarding your message: {refined_response}"
    
    return jsonify(response_data)

def generate_model_response(user_message, emotion=None, max_retries=3):
    if model_data is None:
        return "I'm sorry, but I'm having trouble accessing my knowledge. Please try again later."
    
    try:
        # Format input for T5 model with improved prompt
        prompt = (
            f"Respond in a professional, empathetic, and clear manner to this mental health question:\n\n"
            f"Question: {user_message}\n\n"
        )
        
        if emotion:
            prompt += f"User emotion: {emotion}\n\n"
            
        prompt += "Response:"
        
        for _ in range(max_retries):
            # Tokenize input
            inputs = model_data["tokenizer"](prompt, return_tensors="pt").to(model_data["device"])
            
            # Generate response
            with torch.no_grad():
                output = model_data["model"].generate(
                    inputs.input_ids,
                    max_length=150,
                    temperature=0.8,  # Add some randomness
                    top_p=0.92,       # Control diversity
                    do_sample=True,
                    repetition_penalty=2.0,  # Prevent repetition
                    num_beams=4,
                    early_stopping=True,
                    no_repeat_ngram_size=2
                )
            
            # Decode response
            response = model_data["tokenizer"].decode(output[0], skip_special_tokens=True)
            
            # Ensure response is meaningful and not repetitive
            if len(response.split()) > 5 and not is_repetitive(response):
                recent_responses.append(response)
                if len(recent_responses) > 5:
                    recent_responses.pop(0)
                return response
        
        return f"I understand you're asking about: {user_message}. How can I help you with that specifically?"
    except Exception as e:
        print(f"Error generating model response: {e}")
        import traceback
        traceback.print_exc()
        return f"I'm processing your message about: {user_message}"

def refine_with_gemini(user_message, initial_response, emotion=None):
    # Check for crisis
    is_crisis, crisis_type, _ = detect_crisis(user_message)
    
    # If Gemini is not available, return the initial response
    if gemini_model is None:
        print("Gemini model not available, returning initial response")
        return initial_response
        
    # Add crisis information to the prompt if detected
    crisis_info = ""
    if is_crisis:
        crisis_info = f"""
        IMPORTANT: The user message indicates a potential {crisis_type} crisis. 
        While maintaining a supportive tone, encourage them to seek professional help.
        Be empathetic but clear about the importance of reaching out to crisis services.
        """
    
    prompt = f"""
    User message: {user_message}
    Initial response: {initial_response}
    User emotion: {emotion if emotion else 'unknown'}
    {crisis_info}
    
    You are a supportive friend having a text conversation, NOT an AI. Follow these guidelines:
    1. Use a natural texting style with occasional short sentences
    2. Use some sentence fragments, like real texting
    3. Use contractions (don't, I'm, you're)
    4. Add a personal touch with phrases like "you know" or "hey" or "listen"
    5. Occasionally use lowercase at the start of sentences
    6. Maybe use 1-2 simple emojis if appropriate (but not overdone)
    7. Break up longer thoughts into multiple shorter messages with natural pauses
    8. Be empathetic and warm, but don't sound clinical or therapeutic
    
    Don't explicitly mention being a friend or human - just write naturally.
    If the user is in crisis, still maintain professionalism while keeping the casual tone.
    Keep responses under 100 words total, structured like a text exchange.
    """
    
    try:
        response = gemini_model.generate_content(prompt)
        return response.text
    except Exception as e:
        print(f"Error with Gemini API: {e}")
        return initial_response

@app.route('/inspect_model', methods=['GET'])
def inspect_model_route():
    results = {}
    model_path = os.path.join(os.path.dirname(__file__), "models", "taz_model.tar")
    extracted_dir = os.path.join(os.path.dirname(__file__), "models", "extracted_model")
    
    # Check if file exists
    results["model_exists"] = os.path.exists(model_path)
    results["model_path"] = model_path
    results["extracted_dir_exists"] = os.path.exists(extracted_dir)
    
    if results["model_exists"]:
        # Check file size
        results["file_size_bytes"] = os.path.getsize(model_path)
        results["file_size_mb"] = results["file_size_bytes"] / (1024 * 1024)
        
        # Inspect tar contents
        try:
            with tarfile.open(model_path, "r") as tar:
                results["tar_members"] = tar.getnames()
        except Exception as e:
            results["tar_error"] = str(e)
    
    if results["extracted_dir_exists"]:
        try:
            results["extracted_contents"] = os.listdir(extracted_dir)
        except Exception as e:
            results["extracted_dir_error"] = str(e)
    
    results["model_loaded"] = model_data is not None
    
    return jsonify(results)

@app.route('/test_response', methods=['GET'])
def test_response():
    # Generate a test response
    test_message = "I'm feeling anxious today"
    initial = generate_model_response(test_message, "anxious")
    refined = refine_with_gemini(test_message, initial, "anxious")
    
    return jsonify({
        'status': 'ok',
        'model_loaded': model_data is not None,
        'initial_response': initial,
        'refined_response': refined
    })

@app.route('/test_connection', methods=['GET'])
def test_connection():
    """Simple endpoint to verify the connection between Flutter and Flask"""
    model_info = "custom model" if model_data is not None else "fallback model"
    gemini_status = "available" if gemini_model is not None else "unavailable"
    
    return jsonify({
        'status': 'connected',
        'message': f'Flask backend is running with {model_info}',
        'model_info': model_info,
        'gemini_status': gemini_status
    })

@app.route('/resources', methods=['GET'])
def get_resources():
    resources_dir = os.path.join(os.path.dirname(__file__), "resources")
    refresh = request.args.get('refresh', 'false').lower() == 'true'
    resources = []
    
    # Ensure directory exists
    if not os.path.exists(resources_dir):
        os.makedirs(resources_dir, exist_ok=True)
        # Force refresh if directory was just created
        refresh = True
        
    # If refresh requested or no files exist, trigger scraping
    if refresh or not any(f.startswith('scraped_data_') for f in os.listdir(resources_dir) if os.path.isfile(os.path.join(resources_dir, f))):
        try:
            # Import the scraper function
            from scrape_resources import scrape_website
            
            # List of URLs to scrape
            urls = [
                "https://www.nimh.nih.gov/health/publications/5-action-steps-to-help-someone-having-thoughts-of-suicide",
                "https://www.nimh.nih.gov/health/publications/depression",
                "https://www.nimh.nih.gov/health/publications/generalized-anxiety-disorder-gad",
                "https://www.nimh.nih.gov/health/publications/my-mental-health-do-i-need-help",
                "https://www.nimh.nih.gov/health/publications/panic-disorder-when-fear-overwhelms"
            ]
            
            # Scrape each URL and save to separate files
            for i, url in enumerate(urls):
                filename = os.path.join(resources_dir, f"scraped_data_{i+1}.txt")
                scrape_website(url, filename)
            
            print("Web scraping completed")
        except Exception as e:
            print(f"Error during web scraping: {e}")
            import traceback
            traceback.print_exc()
    
    # Load resources from files
    for i in range(1, 6):  # 5 resources
        filename = os.path.join(resources_dir, f"scraped_data_{i}.txt")
        try:
            if os.path.exists(filename):
                with open(filename, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Extract title if available, otherwise use default
                title = f"Mental Health Resource {i}"
                if content.startswith("TITLE:"):
                    title_end = content.find("\n\n")
                    if title_end > 0:
                        title = content[6:title_end].strip()
                        content = content[title_end:].strip()
                
                resources.append({
                    "title": title,
                    "content": content
                })
            else:
                print(f"Resource file not found: {filename}")
        except Exception as e:
            print(f"Error loading resource {i}: {e}")
    
    return jsonify({
        "resources": resources,
        "updated": refresh
    })

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    if not data:
        return jsonify({"success": False, "error": "No data provided"}), 400
    
    # Extract required fields
    email = data.get('email')
    password = data.get('password')
    name = data.get('name')
    
    print(f"Attempting to register user: {email}, {name}")
    
    if not all([email, password, name]):
        print("Missing required fields")
        return jsonify({"success": False, "error": "Missing required fields"}), 400
    
    # Create new user
    try:
        result = database.create_user(email, password, name)
        print(f"Registration result: {result}")
        
        if result["success"]:
            return jsonify({
                "success": True, 
                "message": "User registered successfully",
                "user_id": result["user_id"]
            }), 201
        else:
            return jsonify({
                "success": False, 
                "error": result.get("error", "Registration failed")
            }), 400
    except Exception as e:
        print(f"Exception during registration: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            "success": False,
            "error": f"Registration error: {str(e)}"
        }), 500

# Add this new endpoint to list users (for debugging only)
@app.route('/list_users', methods=['GET'])
def list_users():
    conn = database.create_connection()
    if conn is not None:
        try:
            cur = conn.cursor()
            cur.execute("SELECT id, email, name FROM users")
            rows = cur.fetchall()
            conn.close()
            
            users = [{"id": row[0], "email": row[1], "name": row[2]} for row in rows]
            return jsonify({"success": True, "users": users})
        except Exception as e:
            conn.close()
            return jsonify({"success": False, "error": str(e)})
    else:
        return jsonify({"success": False, "error": "Database connection failed"})

# Add this new route
@app.route('/therapists', methods=['GET'])
def get_therapists():
    try:
        therapists = get_all_therapists()
        return jsonify(therapists)
    except Exception as e:
        print(f"Error getting therapists: {e}")
        return jsonify({"error": str(e)}), 500

def detect_crisis(message):
    """
    Detects potential crisis indicators in user messages
    Returns a tuple of (is_crisis, crisis_type, confidence_score)
    """
    # Crisis indicators (expand this list)
    crisis_keywords = {
        'suicide': ['kill myself', 'suicide', 'end my life', 'want to die', 'better off dead'],
        'self_harm': ['cut myself', 'hurt myself', 'self harm', 'harming myself', 'burn myself'],
        'violence': ['hurt someone', 'kill someone', 'attack', 'harm others'],
        'immediate_danger': ['right now', 'tonight', 'plan to', 'going to']
    }
    
    message = message.lower()
    
    # Check for crisis indicators
    detected_categories = []
    max_score = 0
    
    for category, keywords in crisis_keywords.items():
        for keyword in keywords:
            if keyword in message:
                # Higher score for immediate danger terms
                score = 0.7
                if category == 'immediate_danger' or any(danger in message for danger in crisis_keywords['immediate_danger']):
                    score = 0.9
                
                detected_categories.append(category)
                max_score = max(max_score, score)
    
    is_crisis = len(detected_categories) > 0
    crisis_type = ', '.join(set(detected_categories)) if detected_categories else None
    
    return (is_crisis, crisis_type, max_score)

# Add this function to get crisis resources
def get_crisis_resources(crisis_type=None):
    """Returns crisis resources based on detected type"""
    # Default crisis resources
    general_resources = [
        "National Suicide Prevention Lifeline: 1-800-273-8255 (24/7)",
        "Crisis Text Line: Text HOME to 741741 (24/7)",
        "SAMHSA's National Helpline: 1-800-662-HELP (4357)"
    ]
    
    # Specialized resources based on crisis type
    specialized_resources = {
        "suicide": [
            "National Suicide Prevention Lifeline: 1-800-273-8255",
            "IMAlive Crisis Chat: www.imalive.org"
        ],
        "self_harm": [
            "S.A.F.E. Alternatives: 1-800-DONT-CUT",
            "Self-Harm Crisis Text Line: Text HOME to 741741"
        ],
        "violence": [
            "National Domestic Violence Hotline: 1-800-799-7233",
            "SAMHSA's National Helpline: 1-800-662-HELP"
        ]
    }
    
    # Combine resources based on crisis type
    if crisis_type and any(t in crisis_type for t in specialized_resources.keys()):
        relevant_resources = []
        for t in specialized_resources.keys():
            if t in crisis_type:
                relevant_resources.extend(specialized_resources[t])
        
        # Add general resources
        relevant_resources.extend([r for r in general_resources if r not in relevant_resources])
        return "\n".join(relevant_resources)
    
    # Return general resources if no specific type or type not in our resource list
    return "\n".join(general_resources)

@app.route('/test_crisis_detection', methods=['POST'])
def test_crisis_detection():
    data = request.json
    message = data.get('message', '')
    
    is_crisis, crisis_type, score = detect_crisis(message)
    resources = get_crisis_resources(crisis_type) if is_crisis else None
    
    return jsonify({
        'is_crisis': is_crisis,
        'crisis_type': crisis_type,
        'confidence_score': score,
        'resources': resources
    })

@app.route('/crisis_resources', methods=['GET'])
def crisis_resources_endpoint():
    crisis_type = request.args.get('type', None)
    resources = get_crisis_resources(crisis_type)
    return jsonify({
        'resources': resources,
        'crisis_type': crisis_type
    })

def analyze_mood_with_gemini(user_message):
    """
    Use Gemini to analyze the user's mood based on their message
    Returns one of: 'Happy', 'Sad', 'Angry', 'Anxious', 'Calm', 'Neutral'
    """
    if gemini_model is None:
        print("Gemini model not available for mood detection")
        return None
    
    try:
        prompt = f"""
        Analyze the emotional state expressed in this message. Choose exactly ONE emotion from this list:
        - Happy (joy, contentment, excitement, gratitude)
        - Sad (sorrow, grief, disappointment, regret)
        - Angry (frustration, annoyance, rage, irritation)
        - Anxious (worry, stress, nervousness, fear)
        - Calm (peaceful, relaxed, composed, content)
        - Neutral (no strong emotion detected)
        
        Respond with ONLY the single word representing the predominant emotion.
        
        Message to analyze: "{user_message}"
        """
        
        response = gemini_model.generate_content(prompt, generation_config={
            "max_output_tokens": 10,
            "temperature": 0.1,  # Keep it deterministic
        })
        
        # Extract and clean the response
        mood = response.text.strip()
        
        # Ensure the response matches one of our categories
        valid_moods = ['Happy', 'Sad', 'Angry', 'Anxious', 'Calm', 'Neutral']
        for valid_mood in valid_moods:
            if valid_mood.lower() in mood.lower():
                print(f"Gemini detected mood: {valid_mood}")
                return valid_mood
        
        print(f"Gemini returned unrecognized mood: {mood}, defaulting to Neutral")
        return 'Neutral'
    except Exception as e:
        print(f"Error in Gemini mood analysis: {e}")
        return None

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
