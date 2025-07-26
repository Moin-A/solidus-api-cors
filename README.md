# Solidus API with CORS

This is a Rails application with Solidus e-commerce platform and CORS configured to allow API requests from localhost:3000.

## Setup

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Set up the database:**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```

3. **Start the server:**
   ```bash
   rails server -p 3001
   ```

## API Endpoints

### Test Endpoint
- **GET** `/api/test`
  - Returns a simple JSON response to test the API
  - No authentication required

### Products Endpoints
- **GET** `/api/products`
  - Returns all available products
  - Requires API key authentication

- **GET** `/api/products/:id`
  - Returns a specific product by ID
  - Requires API key authentication

## CORS Configuration

The application is configured to allow cross-origin requests from:
- `http://127.0.0.1:3000`

CORS settings:
- Allowed methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD
- Credentials: true
- Max age: 86400 seconds (1 day)

## Testing the API

### Test the basic endpoint:
```bash
curl -X GET http://localhost:3001/api/test -H "Content-Type: application/json"
```

### Test CORS from localhost:3000:
```bash
curl -X GET http://localhost:3001/api/test \
  -H "Content-Type: application/json" \
  -H "Origin: http://127.0.0.1:3000"
```

## Frontend Integration

To use this API from a frontend application running on localhost:3000:

```javascript
// Example fetch request
fetch('http://localhost:3001/api/test', {
  method: 'GET',
  headers: {
    'Content-Type': 'application/json',
  },
  credentials: 'include'
})
.then(response => response.json())
.then(data => console.log(data));
```

## Solidus Features

This application includes:
- Solidus e-commerce platform
- Solidus Admin interface (available at `/admin`)
- Solidus Starter Frontend
- PayPal Commerce Platform integration
- Devise authentication
- PostgreSQL database

## Development

- Rails version: 7.1.0
- Ruby version: 3.1.2
- Database: PostgreSQL
- CORS: rack-cors gem
