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

# Load environment variables (for API keys)
load_dotenv()

app = Flask(__name__)
CORS(app)  # Add this line to enable CORS for all routes

# Configure Gemini API
genai.configure(api_key=os.environ.get("GEMINI_API_KEY"))

# Try to get available models first
try:
    available_models = genai.list_models()
    models = [model.name for model in available_models]
    print(f"Available Gemini models: {models}")
    
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
    emotion = data.get('emotion', None)
    
    # Step 1: Generate initial response from your trained model
    initial_response = generate_model_response(user_message, emotion)
    
    # Step 2: Refine the response with Gemini
    refined_response = refine_with_gemini(user_message, initial_response, emotion)
    
    return jsonify({
        'response': refined_response
    })

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
    # If Gemini is not available, return the initial response
    if gemini_model is None:
        print("Gemini model not available, returning initial response")
        return initial_response
        
    prompt = f"""
    User message: {user_message}
    Initial response: {initial_response}
    User emotion: {emotion if emotion else 'unknown'}
    
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

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)