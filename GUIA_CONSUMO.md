# 📡 Ejemplo de Request API - Products

## Método
- **HTTP Method:** `POST`

## URL
- `http://localhost:8080/api/products`

## Headers
```http
Accept: application/json, text/plain, */*
Content-Type: application/json;charset=utf-8

## 🚀 Explicación rápida
- La URL apunta API desplegada en **Azure Container Apps**.  
- Los headers aseguran que el contenido se envía y recibe en formato JSON.  
- El body contiene el objeto `Product` con sus atributos (`name`, `quantity`, `price`).  

{
  "method": "POST",
  "transformRequest": [
    null
  ],
  "transformResponse": [
    null
  ],
  "jsonpCallbackParam": "callback",
  "url": "https://app-maestria-inventario.lemonpond-a9d3a876.eastus.azurecontainerapps.io/api/products",
  "headers": {
    "Accept": "application/json, text/plain, */*",
    "Content-Type": "application/json;charset=utf-8"
  },
  "data": "{\n  \"name\": \"Teclado Mecánico\",\n  \"quantity\": 25,\n  \"price\": 80.0\n}",
  "timeout": {}
}

---
```

## Método
- **HTTP Method:** `GET`

## URL
- `http://localhost:8080/api/products`

## Headers
```http
Accept: application/json, text/plain, */*
Content-Type: application/json;charset=utf-8

[
  {
    "id": "95854bdc-d960-4ba6-88ad-7ef60cc88c26",
    "name": "Mouse",
    "quantity": 25,
    "price": 80
  }
]

```