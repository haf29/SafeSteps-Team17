# Standard Library Imports
import asyncio
import uuid
import json
import re
from datetime import datetime, timezone

# Third-Party Library Imports
import httpx
import boto3
from bs4 import BeautifulSoup
import google.generativeai as genai

# Local Imports
from dynamo import add_incident, update_zone_severity, get_city_items_all


#Config
genai.configure(api_key="AIzaSyBucyCtgozeSKmx5ML8ByEvcdo_IBrFIGU")
model = genai.GenerativeModel("gemini-2.0-flash-lite")

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

#Gemini Analysis
async def analyze_article(article: dict) -> dict: 
    prompt = f""" You are a **public safety incident classifier**.
    Analyze the following news article. 
    Title: {article['title']} 
    Content: {" ".join(article['content']) if isinstance(article['content'], list) else article['content']}
    Task: 1. Determine if this article reports a **real-world public safety hazard or incident in Lebanon**. 
       - Ignore incidents in Gaza, Palestine, West Bank, or any region outside Lebanon. 
       - DO PUT IS_CRIME AS FALSE IN CASE LOCATION IS NOT LEBANON
       - Crimes: murder, assault, robbery, theft, harassment, vandalism 
       - Security/military threats: drone activity, airstrikes, shootings, explosions, kidnappings 
       - Any event that poses a danger to people or public order
    2. If yes: 
       - Extract the most specific location in Lebanon. Make sure the translation of Arabic names to English ones is correct (حربتا becomes Hrabta, etc.)
       - If multiple locations exist, put a list of the most relevant locations(use cities if you feel it reflects the region of threat most)
       - Identify the primary incident type from: ["murder", "assault", "robbery", "theft", "harassment", "vandalism", "drone_activity", "airstrike", "explosion", "shooting", "kidnapping", "other"] 
    3. If not relevant, or location is not Lebanon, set: is_crime=false, crime_type="other", severity_score=0, location=[""]. 
    Return ONLY JSON: 
    {{ 
    "is_crime": true/false, 
    "crime_type": "string", 
    "location": ["string",...] 
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
        print(f"[error] Gemini parsing: {e}")
        article.update(
            {"is_crime": False, "crime_type": "other", "location": "", "severity_score": 0}
        )

    return article


# DynamoDB Helpers
def article_exists(url : str) -> bool:
    try:
        response = table.get_item(Key={"url": url})
        return "Item" in response
    except Exception as e:
        print(f"[error] DynamoDB check: {e}")
        return False


def save_article(article: dict):
    try:
        table.put_item(Item={"url": article.get("url", "")})
    except Exception as e:
        print(f"[error] DynamoDB save: {e}")


#Scraper
async def fetch_content(link: str, incident: dict, source_incidents: list, src: dict):

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
        print(f"[error] fetch_content ({src['name']}): {e}")


async def fetch_articles(source_incidents: list, src: dict, article_count: int):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(src["url"], timeout=10)
            response.raise_for_status()
            data = response.json()

        tasks = []
        for article in data[:article_count]:
            url = article["url"]
            if article_exists(url):
                print(f"[skip] Already exists: {url}")
                continue
            incident = {
                "url": url,
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
        print(f"[error] fetch_articles: {e}")


# Zone + Incident Integration
def save_to_zone(article: dict):
    if not article.get("is_crime", False):
        return

    # Ensure locations is a list
    locations = article.get("location", "Beirut")
    if isinstance(locations, str):
        locations = [locations]

    for city in locations:
        candidates = get_city_items_all(city)
        if not candidates:
            print(f"[skip] No zone found for city {city} -> {article['title']}")
            continue

        # Optionally, you could loop through all zones instead of just the first
        for zone in candidates:
            zone_id = zone["zone_id"]

            ts = datetime.now(timezone.utc)
            incident_type = article["crime_type"]
            severity = article["severity_score"]

            success = add_incident(
                zone_id=zone_id,
                incident_type=incident_type,
                timestamp=ts,
                city=city,
                reported_by="Lebanon Debate",
            )

            if success:
                update_zone_severity(zone_id, severity, ts.isoformat())
                print(f"SUCCESS Zone incident logged: {incident_type} at {city} ({severity})")
            else:
                print(f"FAIL Could not save incident: {article['title']}")


#Main Feed Runner
async def get_feed(src: dict, article_count: int):
    source_incidents = []
    await fetch_articles(source_incidents, src, article_count)

    tasks = [analyze_article(article) for article in source_incidents]
    analyzed = await asyncio.gather(*tasks)

    for art in analyzed:
        save_article(art)
        save_to_zone(art)

    print(json.dumps(analyzed, indent=2, ensure_ascii=False))
    return analyzed


async def main():
    source = {"url": "https://www.lebanondebate.com/api/latest_news", "name": "Lebanon Debate"}
    await get_feed(source, 15)


if __name__ == "__main__":
    asyncio.run(main())
