# SafeSteps 🚶‍♀️🛡️

SafeSteps is a **public-safety mobile application** that helps users navigate urban areas more safely.  
It uses **real-time incident data, geospatial zoning, and machine learning** to provide:

- 🗺️ **Color-coded heatmaps** showing relative zone safety (green = safe, red = risky).
- 🚦 **Safest route recommendations**, avoiding high-risk areas where possible.
- 🆘 **Exit-to-safety guidance**: if a user is already inside a danger zone, the app calculates the nearest safer zone and directs them out immediately.
- 🔮 **Severity prediction**: Users can select a zone and specify a number of days into the future to predict its severity score.

---

## 🌍 Features

- **User authentication** (Signup/Login) — handled via API (AWS Cognito ready).
- **Heatmap overlay** — Google Maps + Uber’s H3 hex zoning.
- **Incident reporting** — crowdsourced + scraped data updates safety scores.
- **Smart routing** — Google Routes API + severity scoring to choose safer paths.
- **Exit to safety** — new feature to direct users out of danger zones.
- **Severity prediction**: Users can select a zone and specify a number of days into the future to predict its severity score.

---

## 🏗️ System Architecture

**Frontend:**  
- Flutter (Dart)  
- Google Maps SDK (with polyline overlays for routes)

**Backend (this repo):**  
- FastAPI (Python)  
- AWS Lambda / API Gateway (deployable)  
- DynamoDB (Zones, Incidents tables)  
- h3-py for geospatial hex handling  

**Data & ML:**  
- Scrapers (BeautifulSoup, Scrapy, Selenium, Puppeteer)  
- AWS S3 (store datasets, ML artifacts)  
- AWS SageMaker (train/predict missing risk data)  

---

## 📂 Repo Structure

```text
SafeSteps-Team17/
├── backend/                 # FastAPI backend
│   ├── api/                 # app entry + routers
│   ├── models/              # Pydantic models
│   ├── services/            # routing, severity, H3 utils, SNS, etc.
│   └── ...
├── frontend/safesteps_app/  # Flutter app
├── lambda/                  # AWS Lambda functions (if deployed)
├── data/                    # city polygons, sample datasets
├── docs/                    # documentation
├── scripts/                 # utility scripts
└── ...
```

---

## 🔧 Local Setup

### Backend (FastAPI)
Fully deployed on EC2

### Frontend (Flutter)
cd frontend/safesteps_app
flutter pub get
flutter run -d chrome   # or your device
```
To run the application:

cd frontend/safesteps_app
Then run the following command: flutter run -d chrome --web-port 8000   --dart-define=WEB_MAPS_ENABLED=true    --dart-define=API_BASE_URL=http://51.20.9.164:8000 --dart-define=API_PREFIX=


---

## 🔑 Environment Variables

All secrets stay private. Commit **`.env.example`**, but keep real **`.env`** out of git (`.gitignore` already covers it).

**`.env.example`**
```env
# --- AWS ---
AWS_REGION=eu-north-1

# Cognito (if used)
COGNITO_USER_POOL_ID=your-user-pool-id
COGNITO_APP_CLIENT_ID=your-app-client-id

# DynamoDB
ZONES_TABLE=Zones
INCIDENTS_TABLE=Incidents
ZONES_CITY_INDEX=city-index

# Geodata
CITY_POLYGONS_FILE=../data/cities.json

# Maps & Routing
MAP_API_KEY=your-google-maps-api-key
# GOOGLE_MAPS_API_KEY=your-google-maps-api-key (if used by backend)
USE_OSRM_ONLY=false
USE_OSRM_FALLBACK=true

# Python path
PYTHONPATH=.
```

---

## 🧑‍🤝‍🧑 Contributors

- Team17 — Amazon Industry Program @ American University of Beirut

---