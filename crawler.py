# Standard Library Imports
import asyncio
import uuid
# Third-Party Library Imports
import httpx
from bs4 import BeautifulSoup
article_Dict = {}


async def fetch_content(
    link: str, incident: dict, source_incidents: list, src: dict
):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(link, timeout=10, follow_redirects=True)
            response.raise_for_status()
            soup = BeautifulSoup(response.text, "html.parser")
        #Get content
        paragraphs = soup.find_all("p", style="font-size: 16px;")
        incident_text = [p.get_text(strip=True) for p in paragraphs if p.get_text(strip=True)]
        #Get title
        container = soup.find("div", class_="article-first-grid")
        title = container.find("h1").get_text(strip=True) if container else None
        incident["title"] = title
        incident["content"] = incident_text
        if len(incident_text) < 1:
            incident["content"] = "No content"
        source_incidents.append(incident)

    except Exception as e:
        print(f"Error in fetch_content ({src['name']}): {e}")


async def get_feed(src: dict, article_count: int):
    source_incidents = []
    await fetch_articles(source_incidents, src, article_count)



async def fetch_articles(
    source_incidents: list, src: dict, article_count: int
):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(src["url"], timeout=10)
            response.raise_for_status()
            data = response.json()
        tasks = []
        i = 0
        for article in data[:article_count]:
            id = uuid.uuid4()
            article = data[i]
            i+=1
            url = article["url"]
            title = article["title"]
            date = article["date"]
            incident = {"url" : url, "id" : id, "date" : date, "content" : "No Content", "title" : title}
            tasks.append(
                asyncio.create_task(
                    fetch_content(
                        incident["url"], incident, source_incidents, src
                    )
                )
            )

        await asyncio.gather(*tasks)
    except Exception as e:
        print(f"Error in fetch_articles: {e}")


async def auto_get_feed(src: dict, article_count: int):
    while True:
        await get_feed(src, article_count)

async def main():
    source = {"url" : "https://www.lebanondebate.com/api/latest_news", "name" : "Lebanon Debate"}
    #Run feed fetching **only once**
    task = asyncio.create_task(get_feed(source, 25))
    await (task)
if __name__ == "__main__":
    asyncio.run(main())