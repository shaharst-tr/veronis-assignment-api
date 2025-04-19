import logging
import json
import azure.functions as func
from datetime import datetime
import os
from azure.cosmos import CosmosClient, exceptions
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient

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

def get_cosmos_connection():
    """Create and return a connection to Cosmos DB."""
    try:
        cosmos_endpoint = get_secret_from_keyvault("cosmos-endpoint")
        cosmos_key = get_secret_from_keyvault("cosmos-key")
        cosmos_database = get_secret_from_keyvault("CosmosDataBase")
        cosmos_container = get_secret_from_keyvault("CosmosContainer")
        
        client = CosmosClient(cosmos_endpoint, cosmos_key)
        database = client.get_database_client(cosmos_database)
        container = database.get_container_client(cosmos_container)
        
        return container
    except Exception as e:
        logging.error(f"Error connecting to Cosmos DB: {str(e)}")
        raise

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

def validate_admin_credentials(req):
    """Validate that the request contains valid admin credentials."""
    try:
        # Get expected admin values from Key Vault
        expected_admin_key = get_secret_from_keyvault("admin-api-key")
        
        # Check for admin key in headers
        req_admin_key = req.headers.get('x-admin-key')
        
        if not req_admin_key:
            # Check if it was passed in query params or body instead
            req_admin_key = req.params.get('admin_key')
            
            if not req_admin_key:
                try:
                    req_body = req.get_json()
                    req_admin_key = req_body.get('admin_key')
                except ValueError:
                    pass
        
        if not req_admin_key:
            logging.warning("Admin authentication failed: No admin key provided")
            return False
            
        # Perform secure comparison of admin keys
        if not expected_admin_key == req_admin_key:
            logging.warning("Admin authentication failed: Invalid admin key")
            return False
            
        logging.info("Admin authentication successful")
        return True
    except Exception as e:
        logging.error(f"Error during admin authentication: {str(e)}")
        return False

def add_restaurant(restaurant_data):
    """Add a new restaurant to Cosmos DB."""
    try:
        container = get_cosmos_connection()
        
        # Validate required fields
        required_fields = ['name', 'style', 'openHour', 'closeHour', 'priceRange']
        for field in required_fields:
            if field not in restaurant_data:
                return False, f"Missing required field: {field}"
        
        # Ensure boolean fields are actually booleans
        boolean_fields = ['vegetarian', 'deliveries']
        for field in boolean_fields:
            if field in restaurant_data and not isinstance(restaurant_data[field], bool):
                if isinstance(restaurant_data[field], str):
                    restaurant_data[field] = restaurant_data[field].lower() == 'true'
                else:
                    return False, f"Field {field} must be a boolean"
        
        # Add metadata
        if 'id' not in restaurant_data:
            # Generate a unique ID by hashing the name and current timestamp
            # Using a more reliable approach than hash() which varies between Python sessions
            import hashlib
            unique_string = f"{restaurant_data['name']}-{datetime.now().isoformat()}"
            restaurant_data['id'] = hashlib.md5(unique_string.encode()).hexdigest()
        
        restaurant_data['createdAt'] = datetime.now().isoformat()
        restaurant_data['updatedAt'] = restaurant_data['createdAt']
        
        # Add to Cosmos DB
        container.create_item(body=restaurant_data)
        logging.info(f"Added new restaurant: {restaurant_data['name']}")
        return True, restaurant_data
    except Exception as e:
        logging.error(f"Error adding restaurant: {str(e)}")
        return False, str(e)

def update_restaurant(restaurant_id, update_data):
    """Update an existing restaurant in Cosmos DB."""
    try:
        container = get_cosmos_connection()
        
        # Check if restaurant exists
        try:
            # Get the existing item
            restaurant_item = container.read_item(item=restaurant_id, partition_key=restaurant_id)
            
            # Update fields
            for field in update_data:
                if field != 'id':  # Don't allow changing the ID
                    restaurant_item[field] = update_data[field]
            
            # Update metadata
            restaurant_item['updatedAt'] = datetime.now().isoformat()
            
            # Save back to Cosmos DB
            updated_item = container.replace_item(item=restaurant_id, body=restaurant_item)
            logging.info(f"Updated restaurant: {restaurant_id}")
            return True, updated_item
        except exceptions.CosmosResourceNotFoundError:
            return False, "Restaurant not found"
    except Exception as e:
        logging.error(f"Error updating restaurant: {str(e)}")
        return False, str(e)

def delete_restaurant(restaurant_id):
    """Delete a restaurant from Cosmos DB."""
    try:
        container = get_cosmos_connection()
        
        # Check if restaurant exists
        try:
            # Delete the item
            container.delete_item(item=restaurant_id, partition_key=restaurant_id)
            logging.info(f"Deleted restaurant: {restaurant_id}")
            return True, "Restaurant deleted successfully"
        except exceptions.CosmosResourceNotFoundError:
            return False, "Restaurant not found"
    except Exception as e:
        logging.error(f"Error deleting restaurant: {str(e)}")
        return False, str(e)

def get_restaurant(restaurant_id):
    """Get a specific restaurant by ID."""
    try:
        container = get_cosmos_connection()
        
        try:
            restaurant = container.read_item(item=restaurant_id, partition_key=restaurant_id)
            return True, restaurant
        except exceptions.CosmosResourceNotFoundError:
            return False, "Restaurant not found"
    except Exception as e:
        logging.error(f"Error getting restaurant: {str(e)}")
        return False, str(e)

def main(req: func.HttpRequest) -> func.HttpResponse:
    """Main function for admin operations on restaurants."""
    logging.info('Admin function processed a request.')
    
    # Gather request details for logging (excluding sensitive information)
    request_log = {
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "method": req.method,
        "url": req.url,
        "query_params": {k: v for k, v in dict(req.params).items() if k.lower() != 'admin_key'},
        "headers": {k: v for k, v in dict(req.headers).items() if k.lower() not in ['x-admin-key', 'authorization']}
    }
    
    # Log the incoming request to Azure Blob Storage
    try:
        log_request_to_blob(request_log)
    except Exception as e:
        logging.error(f"Failed to log request to blob storage: {str(e)}")
    
    # Validate admin credentials
    if not validate_admin_credentials(req):
        return func.HttpResponse(
            json.dumps({
                "error": "Unauthorized access",
                "message": "Valid admin credentials required",
                "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }),
            mimetype="application/json",
            status_code=401
        )
    
    try:
        # Parse request body
        try:
            req_body = req.get_json()
        except ValueError:
            # For GET requests or requests without a body, create an empty dict
            req_body = {}
        
        # Handle both GET and POST requests
        if req.method == "GET":
            # Get action from query params
            action = req.params.get('action', 'list').lower()
            
            if action == 'list':
                # List all restaurants
                try:
                    container = get_cosmos_connection()
                    query = "SELECT * FROM c"
                    restaurants = list(container.query_items(query=query, enable_cross_partition_query=True))
                    
                    return func.HttpResponse(
                        json.dumps({
                            "restaurants": restaurants,
                            "count": len(restaurants),
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=200
                    )
                except Exception as e:
                    logging.error(f"Error listing restaurants: {str(e)}")
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to list restaurants",
                            "message": str(e),
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=500
                    )
            
            elif action == 'get':
                # Get a specific restaurant
                restaurant_id = req.params.get('id')
                
                if not restaurant_id:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Missing parameter",
                            "message": "Restaurant ID is required",
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=400
                    )
                
                success, result = get_restaurant(restaurant_id)
                if success:
                    return func.HttpResponse(
                        json.dumps({
                            "restaurant": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=200
                    )
                else:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to get restaurant",
                            "message": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=404 if result == "Restaurant not found" else 500
                    )
        else:  # POST, PUT, DELETE
            # Route admin operations based on action parameter
            action = req_body.get('action', '').lower()
            
            if action == 'add':
                # Add a new restaurant
                restaurant_data = req_body.get('restaurant')
                if not restaurant_data:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Missing data",
                            "message": "Restaurant data is required",
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=400
                    )
                
                success, result = add_restaurant(restaurant_data)
                if success:
                    return func.HttpResponse(
                        json.dumps({
                            "message": "Restaurant added successfully",
                            "restaurant": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=201
                    )
                else:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to add restaurant",
                            "message": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=400
                    )
            
            elif action == 'update':
                # Update an existing restaurant
                restaurant_id = req_body.get('id')
                update_data = req_body.get('restaurant')
                
                if not restaurant_id or not update_data:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Missing data",
                            "message": "Restaurant ID and update data are required",
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=400
                    )
                
                success, result = update_restaurant(restaurant_id, update_data)
                if success:
                    return func.HttpResponse(
                        json.dumps({
                            "message": "Restaurant updated successfully",
                            "restaurant": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=200
                    )
                else:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to update restaurant",
                            "message": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=404 if result == "Restaurant not found" else 400
                    )
            
            elif action == 'delete':
                # Delete a restaurant
                restaurant_id = req_body.get('id')
                
                if not restaurant_id:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Missing data",
                            "message": "Restaurant ID is required",
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=400
                    )
                
                success, result = delete_restaurant(restaurant_id)
                if success:
                    return func.HttpResponse(
                        json.dumps({
                            "message": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=200
                    )
                else:
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to delete restaurant",
                            "message": result,
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=404 if result == "Restaurant not found" else 400
                    )
            
            elif action == 'list':
                # List all restaurants (admin view - no filtering)
                try:
                    container = get_cosmos_connection()
                    query = "SELECT * FROM c"
                    restaurants = list(container.query_items(query=query, enable_cross_partition_query=True))
                    
                    return func.HttpResponse(
                        json.dumps({
                            "restaurants": restaurants,
                            "count": len(restaurants),
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=200
                    )
                except Exception as e:
                    logging.error(f"Error listing restaurants: {str(e)}")
                    return func.HttpResponse(
                        json.dumps({
                            "error": "Failed to list restaurants",
                            "message": str(e),
                            "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }),
                        mimetype="application/json",
                        status_code=500
                    )
            
            else:
                # Unknown action
                return func.HttpResponse(
                    json.dumps({
                        "error": "Invalid action",
                        "message": f"Unknown admin action: {action}",
                        "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    }),
                    mimetype="application/json",
                    status_code=400
                )
                
    except Exception as e:
        logging.error(f"Error in admin request handler: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "error": "Server error",
                "message": str(e),
                "requestTime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }),
            mimetype="application/json",
            status_code=500
        )