import requests
from bs4 import BeautifulSoup
import os

def scrape_website(url, filename):
    """
    Scrape content from a website and save it to a file
    """
    print(f"Scraping {url}...")
    
    # Send HTTP request
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'}
    try:
        response = requests.get(url, headers=headers, timeout=20)
        
        # Check if request was successful
        if response.status_code == 200:
            # Parse HTML content
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Try more specific content selectors for NIMH website
            main_content = soup.find('div', class_='usa-layout-docs__main')
            
            if not main_content:
                # Fallback to other potential container classes
                main_content = soup.find('article') or soup.find('main') or soup.find('div', class_='main-content')
            
            # If main content found, extract paragraphs from it, otherwise use all paragraphs
            if main_content:
                paragraphs = main_content.find_all('p')
            else:
                paragraphs = soup.find_all('p')
            
            # Create output string
            output = []
            
            # Add title if available
            title = soup.find('h1')
            if title:
                output.append(f"TITLE: {title.get_text().strip()}\n")
            else:
                # Make sure we have some title
                filename_base = os.path.basename(filename)
                output.append(f"TITLE: Mental Health Resource {filename_base.split('_')[-1].split('.')[0]}\n")
            
            # Add paragraphs (excluding reprint information)
            for p in paragraphs:
                text = p.get_text().strip()
                if text:  # Only add non-empty paragraphs
                    # Skip reprint/publication info paragraphs
                    if any(keyword in text.lower() for keyword in ['reprint', 'publication of this document', 'this publication is in the public domain', 'permission is not required']):
                        continue
                        
                    # Skip citation instruction paragraphs
                    if text.lower().startswith('cite this') or 'how to cite' in text.lower():
                        continue
                    
                    # Skip NIH publication numbers
                    if 'nih publication no.' in text.lower() or text.lower().startswith('publication no.'):
                        continue
                    
                    output.append(text)
            
            # Make sure we have some content even if scraping failed to find paragraphs
            if len(output) < 2:
                output.append("Information is currently being updated. Please check back later.")
            
            # Save to text file
            os.makedirs(os.path.dirname(filename), exist_ok=True)
            with open(filename, 'w', encoding='utf-8') as f:
                f.write('\n\n'.join(output))
            
            print(f"Data has been scraped and saved to {filename}")
            return True
        else:
            print(f"Failed to retrieve {url}. Status code: {response.status_code}")
            
            # Create a placeholder file with error information
            os.makedirs(os.path.dirname(filename), exist_ok=True)
            with open(filename, 'w', encoding='utf-8') as f:
                title = os.path.basename(filename).split('_')[-1].split('.')[0]
                f.write(f"TITLE: Mental Health Resource {title}\n\nThis content is temporarily unavailable. Please try refreshing later.")
            
            return False
    except Exception as e:
        print(f"Error scraping {url}: {e}")
        
        # Create a placeholder file with error information
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, 'w', encoding='utf-8') as f:
            title = os.path.basename(filename).split('_')[-1].split('.')[0]
            f.write(f"TITLE: Mental Health Resource {title}\n\nThis content is temporarily unavailable. Please try refreshing later.")
        
        return False

# This allows the file to be run directly for testing
if __name__ == "__main__":
    # Create resources directory if it doesn't exist
    resources_dir = os.path.join(os.path.dirname(__file__), "resources")
    os.makedirs(resources_dir, exist_ok=True)
    
    # List of URLs to scrape
    urls = [
        "https://www.nimh.nih.gov/health/publications/warning-signs-of-suicide",
        "https://www.nimh.nih.gov/health/publications/depression",
        "https://www.nimh.nih.gov/health/publications/borderline-personality-disorder",
        "https://www.nimh.nih.gov/health/publications/my-mental-health-do-i-need-help",
        "https://www.nimh.nih.gov/health/publications/post-traumatic-stress-disorder-ptsd"
    ]
    
    # Scrape each URL and save to separate files
    success_count = 0
    for i, url in enumerate(urls):
        filename = os.path.join(resources_dir, f"scraped_data_{i+1}.txt")
        if scrape_website(url, filename):
            success_count += 1
    
    print(f"Successfully scraped {success_count} out of {len(urls)} resources")