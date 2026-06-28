# zero-waste-backend

Express.js REST API for [Zero-Waste Food Connect](../README.md).

Handles authentication, food listing CRUD, NGO proximity matching, Web Push dispatch, ratings, and file uploads. All business logic lives here; the React frontend talks to this API and subscribes to Supabase Realtime directly.

---

## 🚀 Run Locally

```bash
cp .env.example .env   # fill in all required variables (see below)
npm install
npm run dev            # nodemon → http://localhost:5000
```

Sanity check: `curl http://localhost:5000/health`

### Available Scripts

| Command | What it does |
|---|---|
| `npm start` | Production start (`node server.js`) |
| `npm run dev` | Dev start with nodemon (auto-restart on change) |
| `npm run verify` | Test Supabase connection and check table access |
| `npm run seed` | Seed the database with sample data |
| `npm run seed:wipe` | Wipe all seed data and re-seed |
| `npm test` | Run Jest test suite |
| `npm run lint` | Run ESLint across `src/` |

---

## 🌍 Environment Variables

Create `.env` from `.env.example`:

```env
# Server
PORT=5000
NODE_ENV=development

# Supabase — service role key bypasses RLS (never expose to browser)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# CORS — comma-separated list for multiple origins
FRONTEND_URL=http://localhost:5173

# Google Maps (server-side geocoding only, optional)
GOOGLE_MAPS_API_KEY=

# VAPID — required for Web Push; generate with: npx web-push generate-vapid-keys
VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
VAPID_EMAIL=mailto:admin@yourdomain.com
```

> ⚠️ Never put `SUPABASE_SERVICE_ROLE_KEY` or `VAPID_PRIVATE_KEY` in the frontend `.env`. These are server-only secrets.

---

## 📁 Full Project Structure

```
zero-waste-backend/
├── server.js                      # Entry point — reads PORT, starts HTTP listener
│
├── src/
│   ├── app.js                     # Express app setup: middleware → routes → error handler
│   │
│   ├── config/
│   │   └── supabase.js            # Admin Supabase client (service role — bypasses RLS)
│   │
│   ├── middleware/
│   │   ├── auth.js                # authenticate() — JWT verify + profile load
│   │   │                          # requireRole(...roles) — role-based access control
│   │   ├── errorHandler.js        # Global error handler → JSON { success: false, error }
│   │   ├── upload.js              # Multer instance (memory storage, 5 MB limit, images only)
│   │   │                          # handleUploadErrors() — surfaces Multer errors as 400s
│   │   └── validation.js          # express-validator rule sets + validate() runner
│   │                              # Exports: createFoodValidator, updateProfileValidator,
│   │                              #          nearbyQueryValidator, idParamValidator,
│   │                              #          subscribeValidator, createRatingValidator
│   │
│   ├── routes/
│   │   ├── authRoutes.js          # GET/PATCH /auth/profile
│   │   ├── foodRoutes.js          # Full food listing CRUD + status transitions
│   │   ├── ngoRoutes.js           # GET /ngo/requests  GET /ngo/stats
│   │   ├── notificationRoutes.js  # VAPID key + subscribe + unsubscribe
│   │   ├── ratingRoutes.js        # POST /ratings  GET /ratings/mine  GET /ratings/user/:id
│   │   └── uploadRoutes.js        # POST/DELETE /upload/food-image
│   │
│   ├── controllers/
│   │   ├── authController.js      # getProfile, updateProfile
│   │   ├── foodController.js      # listAvailable, getMine, getStats, getNearby, getOne,
│   │   │                          # createFoodListing, acceptFoodListing, releaseFoodListing,
│   │   │                          # markCollected, cancelListing
│   │   ├── ngoController.js       # getRequests, getStats
│   │   ├── notificationController.js  # getVapidPublicKey, subscribe, unsubscribe
│   │   ├── ratingController.js    # createRating, getMine, getForUser
│   │   └── uploadController.js   # uploadFoodImage, deleteFoodImage
│   │
│   ├── services/
│   │   ├── locationService.js     # findNearbyNGOs(lat, lng, radiusKm) — Haversine in Node
│   │   └── pushService.js         # notifyNGOs(ngos, payload) — web-push.sendNotification()
│   │                              # auto-deletes 410 Gone subscriptions
│   │
│   └── utils/
│       ├── distance.js            # haversineDistance(lat1,lng1,lat2,lng2) (CommonJS)
│       └── geocode.js             # addressToCoords(address) — Google Maps Geocoding API wrapper
│
└── scripts/
    ├── seed.js                    # Insert sample restaurants, NGOs, and food listings
    ├── seed.js --wipe             # Delete seed data before re-inserting
    ├── setup-storage.js           # Create and configure Supabase Storage bucket
    ├── test-realtime.js           # Subscribe to food_listings channel and log events
    └── verify-supabase.js         # Check service role key + table access + RLS policies
```

---

## 🔌 API Reference

**Base path:** `/api/v1`  
**All responses:** `{ "success": true, "data": {...} }` or `{ "success": false, "error": "..." }`

### Auth  — `/api/v1/auth`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| GET | `/profile` | ✓ | any | Return the authenticated user's full profile row |
| PATCH | `/profile` | ✓ | any | Update `name`, `phone`, `address`, `lat`, `lng`, `about`, `service_radius_km` |

Auth endpoints are rate-limited to **20 req / 15 min / IP**.

---

### Food Listings — `/api/v1/food`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| GET | `/` | ✓ | any | All listings with `status = 'available'`, joined with restaurant profile |
| GET | `/mine` | ✓ | restaurant | This restaurant's listings (all statuses), joined with accepting NGO info |
| GET | `/stats` | ✓ | restaurant | `{ mealsDonated, available, accepted, collected, expired }` |
| GET | `/nearby` | ✓ | ngo | Available listings within `?radius=` km of `?lat=&lng=` |
| GET | `/:id` | ✓ | any | Single listing with full restaurant profile join |
| POST | `/` | ✓ | restaurant | Create listing → find nearby NGOs → send push → return `{ listing, notifiedNgoCount }` |
| PATCH | `/:id/accept` | ✓ | ngo | Atomic accept (`WHERE status='available'`) → 409 if already claimed |
| PATCH | `/:id/release` | ✓ | ngo | Release back to `available` so another NGO can claim |
| PATCH | `/:id/collect` | ✓ | ngo | Mark as `collected` → updates `requests.picked_up_at` |
| DELETE | `/:id` | ✓ | restaurant | Cancel listing (`available` or `accepted` only) |

**Food listing statuses:**

```
available ──accept──► accepted ──collect──► collected
         ◄─release───
available / accepted ──cancel──► (deleted)
available / accepted ──cron────► expired
```

---

### NGO — `/api/v1/ngo`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| GET | `/requests` | ✓ | ngo | All requests made by this NGO, joined with food + restaurant data |
| GET | `/stats` | ✓ | ngo | `{ accepted, picked_up, mealsRescued }` |

---

### Notifications — `/api/v1/notifications`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| GET | `/vapid-key` | — | — | Returns `{ publicKey }` for browser `pushManager.subscribe` |
| POST | `/subscribe` | ✓ | any | Save `{ endpoint, keys: { auth, p256dh } }` to `push_subscriptions` |
| DELETE | `/unsubscribe` | ✓ | any | Remove subscription by `?endpoint=` query param |

---

### Ratings — `/api/v1/ratings`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| POST | `/` | ✓ | any | Create rating `{ food_id, ratee_id, stars, comment?, tags?, is_public? }` (one per food_id) |
| GET | `/mine` | ✓ | any | All ratings this user has given |
| GET | `/user/:id` | ✓ | any | Public ratings for user `:id` + `{ avg, total, breakdown }` aggregate |

---

### File Upload — `/api/v1/upload`

| Method | Path | Auth | Role | Description |
|---|---|---|---|---|
| POST | `/food-image` | ✓ | restaurant | Upload `multipart/form-data` field `file` (JPG/PNG/WebP, max 5 MB) → returns `{ url, path, size, type }` |
| DELETE | `/food-image` | ✓ | restaurant, admin | Delete file by `{ path }` from Supabase Storage |

---

### Health

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | — | Returns `{ status: "ok", service, timestamp }` — used by Railway health checks |

---

## 🔐 Auth Middleware

### `authenticate(req, res, next)`

1. Extracts `Bearer <jwt>` from `Authorization` header
2. Calls `supabase.auth.getUser(token)` to verify the JWT
3. Loads the user's full profile from `public.users` (includes `role`)
4. Attaches `req.user = { ...authUser, ...profile }` for downstream use

### `requireRole(...roles)`

Returns middleware that checks `req.user.role` is in the provided list.

```js
// Single role
router.post('/', authenticate, requireRole('restaurant'), c.createFoodListing);

// Multiple roles
router.delete('/food-image', authenticate, requireRole('restaurant', 'admin'), c.delete);
```

Returns `403 Forbidden` with `{ success: false, error: "Forbidden — requires role: restaurant" }` on mismatch.

---

## 📦 Middleware Pipeline

Every request to `/api/v1/*` passes through:

```
Helmet (HTTP headers)
  → CORS (origin whitelist)
    → express.json (body parsing, 2 MB limit)
      → express-rate-limit (200 req / 15 min global)
        → Route-specific middleware
            → authenticate  (verify JWT + load role)
            → requireRole   (role guard, where applicable)
            → validator     (express-validator rules)
            → validate      (runner — returns 400 on failure)
            → controller    (business logic)
              → errorHandler (catch-all JSON error formatter)
```

---

## 📋 Response Shapes

```jsonc
// Success — GET / PATCH
{ "success": true, "data": { ... } }

// Success — POST (created)
{ "success": true, "data": { ... } }   // HTTP 201

// Validation error
{
  "success": false,
  "errors": [
    { "field": "title", "message": "Title is required" },
    { "field": "expiry_time", "message": "Expiry must be in the future" }
  ]
}

// Generic error
{ "success": false, "error": "Listing no longer available" }
```

## 🔢 HTTP Status Code Map

| Code | When |
|---|---|
| `200` | Successful GET / PATCH |
| `201` | Resource created (POST) |
| `400` | Validation failed |
| `401` | Missing or invalid auth token |
| `403` | Authenticated but wrong role |
| `404` | Resource not found |
| `409` | Conflict — e.g. listing already accepted by another NGO |
| `500` | Unexpected server error |

---

## 🏗️ Key Design Patterns

### Atomic accept

Prevents two NGOs from claiming the same listing simultaneously:

```sql
UPDATE food_listings
SET status = 'accepted'
WHERE id = $1 AND status = 'available'   -- guard clause
RETURNING *
```

If `rowCount === 0` → return 409 Conflict.

### Proximity matching

`locationService.findNearbyNGOs(lat, lng, radiusKm)`:

1. Fetch all NGOs with non-null `lat` / `lng` from `public.users`
2. Filter in Node using Haversine distance
3. Return the matching NGO IDs for push dispatch

### Push dispatch

`pushService.notifyNGOs(nearbyNgos, payload)`:

1. Load `push_subscriptions` for each nearby NGO
2. Call `webpush.sendNotification(sub, JSON.stringify(payload))` in parallel
3. Auto-delete subscriptions that return `410 Gone`

---

## 🗄️ Supabase Config

The admin client in `src/config/supabase.js` uses the **service role key** which:
- Bypasses Row Level Security (use only for trusted server-side operations)
- Should **never** be exposed to the browser or committed to version control

For operations where RLS should apply (e.g. reading data on behalf of a specific user), use the user's JWT via `supabase.auth.getUser(token)` and the anon client instead.

---

## 📦 Dependencies

| Package | Version | Purpose |
|---|---|---|
| `express` | 4.21 | HTTP server |
| `@supabase/supabase-js` | 2.45 | DB, Auth, Storage client |
| `cors` | 2.8 | Cross-origin resource sharing |
| `helmet` | 7.1 | Secure HTTP response headers |
| `express-rate-limit` | 7.4 | IP-based rate limiting |
| `express-validator` | 7.2 | Input validation middleware |
| `multer` | 2.1 | Multipart/form-data file parsing |
| `web-push` | 3.6 | VAPID-signed push notifications |
| `axios` | 1.7 | HTTP client (for geocoding calls) |
| `dotenv` | 16.4 | `.env` file loading |
| `nodemon` | 3.1 | Dev auto-restart (devDependency) |
| `jest` + `supertest` | 29.7 / 7.0 | Test runner + HTTP test client (devDependencies) |
