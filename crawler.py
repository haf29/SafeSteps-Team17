# Standard Library Imports
import asyncio
import uuid
import os
import json
import re

# Third-Party Library Imports
import httpx
import google.generativeai as genai
from bs4 import BeautifulSoup

genai.configure(api_key="AIzaSyAIQRCSWDN4E-KsEEz7hYeRdcKByL-UGdI")

model = genai.GenerativeModel("gemini-1.5-flash")

async def analyze_article(article: dict) -> dict:
    """
    Sends article (title + content) to Gemini and asks for classification.
    Returns updated dict with is_domestic_crime and location.
    """
    prompt = f"""
    You are a classifier. Analyze the following news article.

    Title: {article['title']}
    Content: {" ".join(article['content']) if isinstance(article['content'], list) else article['content']}

    Task:
    1. Determine if this article is related to **domestic crime in Lebanon**.
    2. If yes, extract the most specific location mentioned (city, district, or place).
    3. If not related, set location = "".

    Return ONLY a valid JSON object, without any explanation or extra text. 
    Format:
    {{
    "is_domestic_crime": true/false,
    "location": "string"
    }}
    """

    try:
        response = model.generate_content(prompt)
        result_text = response.text.strip()
        #remove Markdown fences if present
        result_text = re.sub(r"^```json|```$", "", result_text, flags=re.MULTILINE).strip()
        result = json.loads(result_text)
        article.update(result)
    except Exception as e:
        print(f"Error parsing Gemini response: {e}")
        article.update({"is_domestic_crime": False, "location": ""})

    return article


async def fetch_content(link: str, incident: dict, source_incidents: list, src: dict):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(link, timeout=10, follow_redirects=True)
            response.raise_for_status()
            soup = BeautifulSoup(response.text, "html.parser")

        # Get content
        paragraphs = soup.find_all("p", style="font-size: 16px;")
        incident_text = [p.get_text(strip=True) for p in paragraphs if p.get_text(strip=True)]

        # Get title
        container = soup.find("div", class_="article-first-grid")
        title = container.find("h1").get_text(strip=True) if container else None

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
    """Gets and analyzes a batch of articles from a source."""
    source_incidents = []
    await fetch_articles(source_incidents, src, article_count)

    # Analyze each article with Gemini
    tasks = [analyze_article(article) for article in source_incidents]
    analyzed = await asyncio.gather(*tasks)

    print(json.dumps(analyzed, indent=2, ensure_ascii=False))
    return analyzed
#need to save to database, after that we can only go over stuff we haven't already seen in fetch articles(we dont add it to our dict) instead, we skip over them(if we already saw that url) 


async def main():
    source = {"url": "https://www.lebanondebate.com/api/latest_news", "name": "Lebanon Debate"}
    await get_feed(source, 5)


if __name__ == "__main__":
    asyncio.run(main())
