import logging
import json
import azure.functions as func
from datetime import datetime
import os
from azure.cosmos import CosmosClient, exceptions
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient  # Import for blob storage

# Cache for Key Vault secrets to avoid repeated calls
_secret_cache = {}

def get_secret_from_keyvault(secret_name):
    """Retrieve a secret from Azure Key Vault with caching."""
    if secret_name in _secret_cache:
        return _secret_cache[secret_name]
    
    try:
        key_vault_url = os.environ["KEY_VAULT_URL"]
        credential = DefaultAzureCredential()
        secret_client = SecretClient(vault_url=key_vault_url, credential=credential)
        secret = secret_client.get_secret(secret_name).value
        _secret_cache[secret_name] = secret
        
        logging.info(f"Successfully retrieved secret '{secret_name}' from Key Vault")
        return secret
    except Exception as e:
        logging.error(f"Error retrieving secret '{secret_name}' from Key Vault: {str(e)}")
        # Fallback to environment variable
        fallback = os.environ.get(secret_name)
        if fallback:
            logging.warning(f"Using fallback from environment variable for '{secret_name}'")
            return fallback
        raise

def get_restaurants_from_cosmos_db():
    """Fetch restaurants from Cosmos DB using secrets from Key Vault."""
    try:
        cosmos_endpoint = get_secret_from_keyvault("cosmos-endpoint")
        cosmos_key = get_secret_from_keyvault("cosmos-key")
        cosmos_database = get_secret_from_keyvault("CosmosDataBase")
        cosmos_container = get_secret_from_keyvault("CosmosContainer")
        
        client = CosmosClient(cosmos_endpoint, cosmos_key)
        database = client.get_database_client(cosmos_database)
        container = database.get_container_client(cosmos_container)
        
        query = "SELECT * FROM c"
        restaurants = list(container.query_items(query=query, enable_cross_partition_query=True))
        
        logging.info(f"Successfully fetched {len(restaurants)} restaurants from Cosmos DB")
        return restaurants
        
    except Exception as e:
        logging.error(f"Error fetching restaurants from Cosmos DB: {str(e)}")
        logging.warning("Falling back to hardcoded restaurant list")
        return get_hardcoded_restaurants()

def get_hardcoded_restaurants():
    """Return the hardcoded restaurants list as a fallback."""
    return [
        # ... your existing hardcoded restaurant list ...
    ]

def is_restaurant_open(open_hour, close_hour):
    """Check if the restaurant is currently open based on the current time."""
    current_time = datetime.now().strftime("%H:%M")
    logging.info(f"Checking if open: current_time={current_time}, open_hour={open_hour}, close_hour={close_hour}")
    
    if close_hour < open_hour:
        result = current_time >= open_hour or current_time <= close_hour
        logging.info(f"After-midnight case: result={result}")
        return result
    
    result = open_hour <= current_time <= close_hour
    logging.info(f"Normal case: result={result}")
    return result

def filter_restaurants(query_params, restaurants):
    """Filter restaurants based on query parameters."""
    filtered = restaurants.copy()
    current_time = datetime.now().strftime("%H:%M")
    logging.info(f"Current time is: {current_time}")
    
    # Filter by open status - only include restaurants that are currently open
    filtered = [r for r in filtered if is_restaurant_open(r['openHour'], r['closeHour'])]
    logging.info(f"After open status filtering: {len(filtered)} restaurants are currently open")
    
    if 'style' in query_params:
        style_param = query_params['style'].lower()
        filtered = [r for r in filtered if r['style'].lower() == style_param]
        logging.info(f"After style filtering: {len(filtered)} restaurants match {style_param}")
    
    if 'vegetarian' in query_params:
        veg_param = query_params['vegetarian'].lower() == 'true'
        filtered = [r for r in filtered if r['vegetarian'] == veg_param]
        logging.info(f"After vegetarian filtering: {len(filtered)} restaurants match vegetarian={veg_param}")
    
    if 'deliveries' in query_params:
        delivery_param = query_params['deliveries'].lower() == 'true'
        filtered = [r for r in filtered if r['deliveries'] == delivery_param]
        logging.info(f"After delivery filtering: {len(filtered)} restaurants match deliveries={delivery_param}")
    
    if 'priceRange' in query_params:
        price_param = query_params['priceRange']
        filtered = [r for r in filtered if r['priceRange'] == price_param]
        logging.info(f"After price range filtering: {len(filtered)} restaurants match priceRange={price_param}")
    
    if 'openNow' in query_params and query_params['openNow'].lower() == 'false':
        temp = restaurants.copy()
        if 'style' in query_params:
            style_param = query_params['style'].lower()
            temp = [r for r in temp if r['style'].lower() == style_param]
        
        if 'vegetarian' in query_params:
            veg_param = query_params['vegetarian'].lower() == 'true'
            temp = [r for r in temp if r['vegetarian'] == veg_param]
        
        if 'deliveries' in query_params:
            delivery_param = query_params['deliveries'].lower() == 'true'
            temp = [r for r in temp if r['deliveries'] == delivery_param]
        
        if 'priceRange' in query_params:
            price_param = query_params['priceRange']
            temp = [r for r in temp if r['priceRange'] == price_param]
        
        filtered = temp
        logging.info("openNow=false was specified, showing all matching restaurants regardless of open status")
    
    return filtered

def log_request_to_blob(request_data: dict):
    """
    Log the given request data to an Azure Blob Storage container.
    
    This function retrieves the connection string and the container name from the Key Vault.
    If LOG_CONTAINER_NAME is not set in Key Vault, the container name defaults to 'function-logs'.
    Each log is stored as a separate blob with a unique name.
    """
    try:
        # Get blob connection info from Key Vault
        storage_conn_str = get_secret_from_keyvault("BlobStorageConnStr")
        # Retrieve container name from KV; use default if secret is empty or missing.
        container_name = get_secret_from_keyvault("BlobContainerName") or "function-logs"
        
        blob_service_client = BlobServiceClient.from_connection_string(storage_conn_str)
        container_client = blob_service_client.get_container_client(container_name)
        
        # Create the container if it doesn't exist.
        try:
            container_client.create_container()
        except Exception:
            # The container likely already exists.
            pass
        
        # Create a unique blob name using UTC timestamp and random bytes.
        blob_name = f"{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}_{os.urandom(4).hex()}.json"
        blob_data = json.dumps(request_data, indent=2)
        
        container_client.upload_blob(name=blob_name, data=blob_data)
        logging.info(f"Logged request to blob storage as {blob_name}")
    except Exception as e:
        # Log any errors encountered during the logging process.
        logging.error(f"Error logging request to blob: {str(e)}")

def main(req: func.HttpRequest) -> func.HttpResponse:
    """Main function to handle HTTP requests for restaurant recommendations."""
    logging.info('Restaurant recommendation function processed a request.')
    
    # Gather request details for logging.
    request_log = {
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "method": req.method,
        "url": req.url,
        "query_params": dict(req.params),
        # Be cautious when logging headers; include only what is necessary.
        "headers": {key: req.headers.get(key) for key in req.headers}
    }
    
    # Log the incoming request to Azure Blob Storage.
    try:
        log_request_to_blob(request_log)
    except Exception as e:
        logging.error(f"Failed to log request to blob storage: {str(e)}")
    
    try:
        # Get query parameters from the URL.
        query_params = {}
        for param_name in req.params:
            query_params[param_name] = req.params[param_name]
        
        # Merge JSON body parameters (for POST requests) with query parameters.
        try:
            req_body = req.get_json()
            if req_body:
                for key, value in req_body.items():
                    query_params[key] = value
        except ValueError:
            pass  # No JSON body or invalid JSON.
        
        current_time = datetime.now()
        logging.info(f"Request received at {current_time} ({current_time.hour}:{current_time.minute})")
        logging.info(f"Query parameters: {query_params}")
        
        # Retrieve restaurants from Cosmos DB (with a fallback to hardcoded data).
        restaurants = get_restaurants_from_cosmos_db()
        logging.info(f"Total restaurants before filtering: {len(restaurants)}")
        
        if 'openNow' in query_params:
            logging.info(f"openNow parameter specified: {query_params['openNow']}")
        else:
            logging.info("No openNow parameter specified, filtering for currently open restaurants by default")
        
        matching_restaurants = filter_restaurants(query_params, restaurants)
        
        if matching_restaurants:
            # Add an "isOpenNow" flag to each restaurant.
            for restaurant in matching_restaurants:
                restaurant["isOpenNow"] = is_restaurant_open(restaurant["openHour"], restaurant["closeHour"])
            
            recommendation = {
                "restaurants": matching_restaurants,
                "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "totalMatches": len(matching_restaurants)
            }
            
            log_data = {
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "query_params": query_params,
                "result": "success",
                "matches": len(matching_restaurants)
            }
            logging.info(f"REQUEST LOG: {json.dumps(log_data)}")
            
            return func.HttpResponse(
                json.dumps(recommendation, indent=2),
                mimetype="application/json",
                status_code=200
            )
        else:
            log_data = {
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "query_params": query_params,
                "result": "no_match"
            }
            logging.info(f"REQUEST LOG: {json.dumps(log_data)}")
            
            return func.HttpResponse(
                json.dumps({
                    "message": "No restaurants match your criteria",
                    "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }),
                mimetype="application/json",
                status_code=404
            )
            
    except Exception as e:
        log_data = {
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "error": str(e)
        }
        logging.error(f"ERROR LOG: {json.dumps(log_data)}")
        
        return func.HttpResponse(
            json.dumps({
                "error": "An error occurred processing your request",
                "details": str(e),
                "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }),
            mimetype="application/json",
            status_code=500
        )
