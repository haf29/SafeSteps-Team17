# SafeSteps 🚶‍♀️🛡️
Note : This will be subject to further change since project still under construction 

SafeSteps is a **public-safety mobile application** that helps users navigate urban areas more safely.  
It uses **real-time incident data, geospatial zoning, and machine learning** to provide:

- 🗺️ **Color-coded heatmaps** showing relative zone safety (green = safe, red = risky).
- 🚦 **Safest route recommendations**, avoiding high-risk areas where possible.
- 📲 **Instant SMS/push alerts** if a user enters or approaches a danger zone.
- 🆘 **Exit-to-safety guidance**: if a user is already inside a danger zone, the app calculates the nearest safer zone and directs them out immediately.

---

## 🌍 Features

- **User authentication** (Signup/Login) — handled via API (AWS Cognito ready).
- **Heatmap overlay** — Google Maps + Uber’s H3 hex zoning.
- **Incident reporting** — crowdsourced + scraped data updates safety scores.
- **Smart routing** — Google Routes API + severity scoring to choose safer paths.
- **Exit to safety** — new feature to direct users out of danger zones.
- **Notifications** — AWS SNS SMS alerts when internet connectivity is limited.

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

**Notifications:**  
- AWS SNS (SMS + push)

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
```bash
cd backend/api
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
cp .env.example .env    # fill with your private values
uvicorn main:app --reload
```
Open Swagger: `http://127.0.0.1:8000/docs`

### Frontend (Flutter)
```bash
cd frontend/safesteps_app
flutter pub get
flutter run -d chrome   # or your device
```

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

## 🔗 Important Endpoints (Backend)

- `POST /user/signup`, `POST /user/confirm`, `POST /user/login`
- `GET /hex_zones_lebanon` — preload all zones
- `GET /hex_zones?lat=..&lng=..` — zones around a point
- `POST /route/safest` — compute safest route between two points
- `POST /route/exit_to_safety` — compute nearest safe exit from current position
- `POST /report_incident` — report an incident
- `GET /health` — service check

(Full list in Swagger at `/docs`.)

---

## 📱 Example SMS Alerts

1. `SafeSteps Alert: Incident reported near {neighborhood}. Severity {level}. Avoid area for {duration}. Reply STOP to opt out.`  
2. `SafeSteps: You’re inside a high-risk zone. Follow link to the nearest safe exit: {short_url}. Reply STOP to opt out.`  
3. `SafeSteps verification code: {code}. It expires in 10 minutes.`

---

## 🧑‍🤝‍🧑 Contributors

- Team17 — Amazon Industry Program @ American University of Beirut

---

## 📝 Notes for AWS Reviewers

- SMS messages are **transactional only** (safety alerts, verification codes, critical notifications).  
- Users **opt-in** during signup; they may **opt-out** in-app or via **STOP** replies where supported.  
- We comply with **AWS AUP** and regional telecom rules.  
- Initial geography: Lebanon + EU; global-ready.
