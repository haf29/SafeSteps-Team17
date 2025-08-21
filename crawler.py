# Standard Library Imports
import asyncio
import uuid
import json
import re

# Third-Party Library Imports
import httpx
import boto3
from decimal import Decimal
import google.generativeai as genai
from bs4 import BeautifulSoup

def convert_floats(obj):
    """
    Recursively convert float values in a dict/list to Decimal
    so that DynamoDB accepts them.
    """
    if isinstance(obj, list):
        return [convert_floats(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: convert_floats(v) for k, v in obj.items()}
    elif isinstance(obj, float):
        return Decimal(str(obj))  # Convert float -> string -> Decimal
    else:
        return obj  

# Configure Gemini
genai.configure(api_key="AIzaSyBucyCtgozeSKmx5ML8ByEvcdo_IBrFIGU") #Gemini key
model = genai.GenerativeModel("gemini-1.5-flash")
#Dynamo Db
dynamodb = boto3.resource("dynamodb", region_name="eu-north-1")
table = dynamodb.Table("Articles")

SEVERITY_WEIGHTS: dict[str, float] = {
    "murder": 10.0,
    "assault": 7.0,
    "robbery": 5.5,
    "theft": 4.0,
    "harassment": 2.0,
    "vandalism": 2.5,
    "drone_activity": 1.5,
    "airstrike": 9.0,
    "explosion": 6.5,
    "shooting": 8.0,
    "kidnapping": 7.5,
    "other": 1.0,
}

async def analyze_article(article: dict) -> dict:
    prompt = f"""
    You are a **public safety incident classifier**. Analyze the following news article.

    Title: {article['title']}
    Content: {" ".join(article['content']) if isinstance(article['content'], list) else article['content']}

    Task:
    1. Determine if this article reports a **real-world public safety hazard or incident in Lebanon**.
    - Ignore incidents in Gaza, Palestine, West Bank, or any region outside Lebanon.
    - Crimes: murder, assault, robbery, theft, harassment, vandalism
    - Security/military threats: drone activity, airstrikes, shootings, explosions, kidnappings
    - Any event that poses a danger to people or public order
    2. If yes:
        - Extract the most specific location in Lebanon.
        - Identify the primary incident type from:
        ["murder", "assault", "robbery", "theft", "harassment", "vandalism",
        "drone_activity", "airstrike", "explosion", "shooting", "kidnapping", "other"]
    3. If not relevant, set:
    is_crime=false, crime_type="other", severity_score=0, location="".

    Return ONLY JSON:
    {{
    "is_crime": true/false,
    "crime_type": "string",
    "location": "string"
    }}
    """
    try:
        response = model.generate_content(prompt)
        result_text = response.text.strip()
        result_text = re.sub(r"^```json|```$", "", result_text, flags=re.MULTILINE).strip()
        result = json.loads(result_text)

        severity = SEVERITY_WEIGHTS.get(result.get("crime_type", "other").lower(), 1.0)
        result["severity_score"] = severity
        article.update(result)

    except Exception as e:
        print(f"Error parsing Gemini response: {e}")
        article.update(
            {"is_crime": False, "crime_type": "other", "location": "", "severity_score": 0}
        )

    return article

def article_exists(url: str) -> bool:
    #Check if article with this URL exists in DB
    try:
        response = table.get_item(Key={"url": url})
        return "Item" in response
    except Exception as e:
        print(f"DynamoDB check error: {e}")
        return False
    
def save_article(article: dict):
    """Save analyzed article to DynamoDB."""
    try:
        article = convert_floats(article)
        if article.get("is_crime", False):
            table.put_item(Item=article)
    except Exception as e:
        print(f"DynamoDB save error: {e}")

async def fetch_content(link: str, incident: dict, source_incidents: list, src: dict):
    if article_exists(link):
        print(f"Skipping (already exists in DB): {link}") #could be commented when depoyed(would need logging for thigns to show)
        return

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(link, timeout=10, follow_redirects=True)
            response.raise_for_status()
            soup = BeautifulSoup(response.text, "html.parser")

        paragraphs = soup.find_all("p", style="font-size: 16px;")
        incident_text = [p.get_text(strip=True) for p in paragraphs if p.get_text(strip=True)]

        container = soup.find("div", class_="article-first-grid")
        title = container.find("h1").get_text(strip=True) if container else incident["title"]

        incident["title"] = title
        incident["content"] = incident_text if incident_text else "No content"

        source_incidents.append(incident)

    except Exception as e:
        print(f"Error in fetch_content ({src['name']}): {e}")

async def fetch_articles(source_incidents: list, src: dict, article_count: int):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(src["url"], timeout=10)
            response.raise_for_status()
            data = response.json()

        tasks = []
        for article in data[:article_count]:
            incident = {
                "url": article["url"],
                "id": str(uuid.uuid4()),
                "date": article["date"],
                "content": "No Content",
                "title": article["title"],
            }
            tasks.append(
                asyncio.create_task(fetch_content(incident["url"], incident, source_incidents, src))
            )

        await asyncio.gather(*tasks)

    except Exception as e:
        print(f"Error in fetch_articles: {e}")

async def get_feed(src: dict, article_count: int):
    source_incidents = []
    await fetch_articles(source_incidents, src, article_count)

    tasks = [analyze_article(article) for article in source_incidents]
    analyzed = await asyncio.gather(*tasks)

    for art in analyzed:
        save_article(art)

    print(json.dumps(analyzed, indent=2, ensure_ascii=False))
    return analyzed

async def main():
    source = {"url": "https://www.lebanondebate.com/api/latest_news", "name": "Lebanon Debate"}
    await get_feed(source, 5)

if __name__ == "__main__":
    asyncio.run(main())
