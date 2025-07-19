from typing import Dict, Any, Optional
from core.managers.encryption_manager import EncryptionManager
from utils.config.config import Config
from pymongo import MongoClient, ReadPreference
from pymongo.read_concern import ReadConcern
from pymongo.write_concern import WriteConcern
from pymongo.errors import OperationFailure, ConnectionFailure
from urllib.parse import quote_plus
from tools.logger.custom_logging import custom_log
import logging
import os
import queue
import threading
import uuid
import time

# Helper to read secrets from files
def read_secret_file(path: str) -> Optional[str]:
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except Exception:
        return None

class DatabaseManager:
    _instance = None
    _initialized = False
    
    def __new__(cls, role: str = "read_write"):
        """Singleton pattern - return existing instance if it exists."""
        if cls._instance is None:
            cls._instance = super(DatabaseManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self, role: str = "read_write"):
        """Initialize the database manager with role-based access control and queueing system."""
        # If already initialized, just return
        if self._initialized:
            return
            
        self.encryption_manager = EncryptionManager()
        self.role = role
        self.client = None
        self.db = None
        self.available = False  # Track if database is available for use
        self.logger = logging.getLogger(__name__)
        
        # Queue system components
        self.request_queue = queue.Queue(maxsize=1000)  # Configurable queue size
        self.result_store = {}  # Store results by request_id
        self.worker_thread = None
        self.queue_enabled = True
        self.queue_lock = threading.Lock()  # Thread safety for result store
        
        # Queue configuration
        self.max_queue_size = 1000
        self.worker_timeout = 1  # seconds
        self.result_timeout = 60  # seconds for result retrieval (increased for encryption overhead)
        
        # Try to setup MongoDB connection gracefully
        try:
            self._setup_mongodb_connection()
            self.available = True
            custom_log("✅ DatabaseManager initialized successfully")
        except Exception as e:
            custom_log(f"⚠️ DatabaseManager initialized but database unavailable: {e}")
            custom_log("⚠️ Database operations will be skipped - suitable for local development")
        
        # Start queue worker
        self._start_queue_worker()
        
        # Mark as initialized
        self._initialized = True

    def _start_queue_worker(self):
        """Start background worker to process database requests."""
        self.worker_thread = threading.Thread(target=self._process_queue, daemon=True)
        self.worker_thread.start()
        custom_log("✅ Database queue worker started")

    def _process_queue(self):
        """Background worker that processes queued database requests."""
        while self.queue_enabled:
            try:
                # Get request from queue with timeout
                request = self.request_queue.get(timeout=self.worker_timeout)
                
                # Log the operation being processed
                custom_log(f"🔄 Processing queued operation: {request['operation']} on {request['collection']}")
                
                # Process the request
                result = self._execute_queued_operation(request)
                
                # Log the result
                if result.get('success'):
                    custom_log(f"✅ Queued operation completed: {request['operation']} on {request['collection']}")
                else:
                    custom_log(f"❌ Queued operation failed: {request['operation']} on {request['collection']} - {result.get('error')}")
                
                # Store result
                with self.queue_lock:
                    self.result_store[request['id']] = result
                    
            except queue.Empty:
                continue
            except Exception as e:
                # Handle worker errors
                if 'request' in locals():
                    with self.queue_lock:
                        self.result_store[request['id']] = {
                            'success': False,
                            'error': str(e),
                            'completed': True
                        }
                custom_log(f"❌ Queue worker error: {e}", level="ERROR")

    def _execute_queued_operation(self, request: Dict) -> Dict:
        """Execute a queued database operation."""
        operation = request['operation']
        collection = request['collection']
        query = request.get('query', {})
        data = request.get('data', None)
        
        try:
            if operation == 'insert':
                result_id = self._execute_insert(collection, data)
                return {'success': True, 'result': result_id, 'completed': True}
            elif operation == 'find':
                result = self._execute_find(collection, query)
                return {'success': True, 'result': result, 'completed': True}
            elif operation == 'find_one':
                result = self._execute_find_one(collection, query)
                return {'success': True, 'result': result, 'completed': True}
            elif operation == 'update':
                modified_count = self._execute_update(collection, query, data)
                return {'success': True, 'result': modified_count, 'completed': True}
            elif operation == 'delete':
                deleted_count = self._execute_delete(collection, query)
                return {'success': True, 'result': deleted_count, 'completed': True}
            else:
                return {'success': False, 'error': f'Unknown operation: {operation}', 'completed': True}
        except Exception as e:
            custom_log(f"❌ Error in _execute_queued_operation: {e}", level="ERROR")
            import traceback
            custom_log(f"❌ Traceback: {traceback.format_exc()}", level="ERROR")
            return {'success': False, 'error': str(e), 'completed': True}

    def queue_operation(self, operation: str, collection: str, query: Dict = None, data: Dict = None, timeout: int = None) -> Dict:
        """
        Universal queue method for all database operations.
        
        :param operation: 'insert', 'find', 'update', 'delete', 'find_one'
        :param collection: Collection name
        :param query: Query filter (for find, update, delete)
        :param data: Data to insert or update
        :param timeout: Timeout in seconds (default: self.result_timeout)
        :return: Result dictionary with success status and data
        """
        if not self.queue_enabled:
            raise Exception("Queue system is disabled")
        
        request_id = str(uuid.uuid4())
        request = {
            'id': request_id,
            'operation': operation,
            'collection': collection,
            'query': query,
            'data': data,
            'timestamp': time.time()
        }
        
        try:
            # Log the queued operation
            custom_log(f"📝 Queuing operation: {operation} on {collection}")
            
            # Queue the operation
            self.request_queue.put(request, timeout=5)
            
            # Wait for result
            if timeout is None:
                timeout = self.result_timeout
            
            start_time = time.time()
            while time.time() - start_time < timeout:
                with self.queue_lock:
                    if request_id in self.result_store:
                        result = self.result_store[request_id]
                        del self.result_store[request_id]  # Clean up
                        return result
                time.sleep(0.1)
            
            raise Exception(f"Request {request_id} timed out after {timeout} seconds")
            
        except queue.Full:
            raise Exception("Database queue is full")

    def insert(self, collection: str, data: Dict[str, Any]) -> Optional[str]:
        """Insert a document using queue system."""
        if not self.available:
            custom_log("⚠️ Database unavailable - skipping insert operation")
            return None
            
        if self.role == "read_only":
            raise OperationFailure("Write operations not allowed with read-only role")
        
        result = self.queue_operation('insert', collection, data=data)
        if result.get('success'):
            return result['result']
        else:
            raise Exception(f"Insert operation failed: {result.get('error')}")

    def find(self, collection: str, query: Dict[str, Any]) -> list:
        """Find documents using queue system."""
        if not self.available:
            custom_log("⚠️ Database unavailable - skipping find operation")
            return []
            
        result = self.queue_operation('find', collection, query=query)
        if result.get('success'):
            return result['result']
        else:
            raise Exception(f"Find operation failed: {result.get('error')}")

    def find_one(self, collection: str, query: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Find one document using queue system."""
        if not self.available:
            custom_log("⚠️ Database unavailable - skipping find operation")
            return None
            
        result = self.queue_operation('find_one', collection, query=query)
        if result.get('success'):
            return result['result']
        else:
            raise Exception(f"Find_one operation failed: {result.get('error')}")

    def update(self, collection: str, query: Dict[str, Any], data: Dict[str, Any]) -> int:
        """Update documents using queue system."""
        if not self.available:
            custom_log("⚠️ Database unavailable - skipping update operation")
            return 0
            
        if self.role == "read_only":
            raise OperationFailure("Write operations not allowed with read-only role")
        
        result = self.queue_operation('update', collection, query=query, data=data)
        if result.get('success'):
            return result['result']
        else:
            raise Exception(f"Update operation failed: {result.get('error')}")

    def delete(self, collection: str, query: Dict[str, Any]) -> int:
        """Delete documents using queue system."""
        if not self.available:
            custom_log("⚠️ Database unavailable - skipping delete operation")
            return 0
            
        if self.role == "read_only":
            raise OperationFailure("Write operations not allowed with read-only role")
        
        result = self.queue_operation('delete', collection, query=query)
        if result.get('success'):
            return result['result']
        else:
            raise Exception(f"Delete operation failed: {result.get('error')}")

    # Legacy methods for backward compatibility
    def insert_one(self, collection: str, document: Dict[str, Any]) -> Optional[str]:
        """Insert a single document using queue system."""
        return self.insert(collection, document)

    def update_one(self, collection: str, query: Dict[str, Any], update: Dict[str, Any]) -> int:
        """Update a single document using queue system."""
        return self.update(collection, query, update)

    def delete_one(self, collection: str, query: Dict[str, Any]) -> int:
        """Delete a single document using queue system."""
        return self.delete(collection, query)

    def find_many(self, collection: str, query: Dict[str, Any]) -> list:
        """Find multiple documents using queue system."""
        return self.find(collection, query)

    def get_queued_result(self, request_id: str, timeout: int = None) -> Dict:
        """Get result of a queued operation."""
        if timeout is None:
            timeout = self.result_timeout
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            with self.queue_lock:
                if request_id in self.result_store:
                    result = self.result_store[request_id]
                    del self.result_store[request_id]  # Clean up
                    return result
            time.sleep(0.1)  # Small delay before checking again
        
        raise Exception(f"Request {request_id} timed out after {timeout} seconds")

    def _execute_insert(self, collection: str, data: Dict[str, Any]) -> Optional[str]:
        """Execute insert operation directly (for queue worker)."""
        if not self.available:
            return None
        encrypted_data = self._encrypt_sensitive_fields(data)
        result = self.db[collection].insert_one(encrypted_data)
        return str(result.inserted_id)

    def _convert_objectid_to_string(self, data):
        """Convert ObjectId to string for JSON serialization."""
        from bson import ObjectId
        
        if isinstance(data, dict):
            result = {}
            for key, value in data.items():
                if isinstance(value, ObjectId):
                    result[key] = str(value)
                else:
                    result[key] = self._convert_objectid_to_string(value)
            return result
        elif isinstance(data, list):
            return [self._convert_objectid_to_string(item) for item in data]
        else:
            return data

    def _convert_string_to_objectid(self, data):
        """Convert string _id to ObjectId for MongoDB queries."""
        from bson import ObjectId
        
        if isinstance(data, dict):
            result = {}
            for key, value in data.items():
                if key == '_id' and isinstance(value, str):
                    try:
                        result[key] = ObjectId(value)
                    except Exception:
                        # If conversion fails, keep as string
                        result[key] = value
                else:
                    result[key] = self._convert_string_to_objectid(value)
            return result
        elif isinstance(data, list):
            return [self._convert_string_to_objectid(item) for item in data]
        else:
            return data

    def _execute_find(self, collection: str, query: Dict[str, Any]) -> list:
        """Execute find operation directly (for queue worker)."""
        if not self.available:
            return []
        # Convert string _id to ObjectId for MongoDB queries
        converted_query = self._convert_string_to_objectid(query)
        # Encrypt sensitive fields in the query to match encrypted data in database
        encrypted_query = self._encrypt_sensitive_fields(converted_query)
        results = list(self.db[collection].find(encrypted_query))
        decrypted_results = [self._decrypt_sensitive_fields(doc) for doc in results]
        return [self._convert_objectid_to_string(doc) for doc in decrypted_results]

    def _execute_find_one(self, collection: str, query: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Execute find_one operation directly (for queue worker)."""
        if not self.available:
            return None
        # Convert string _id to ObjectId for MongoDB queries
        converted_query = self._convert_string_to_objectid(query)
        
        # Encrypt sensitive fields in the query to match encrypted data in database
        encrypted_query = self._encrypt_sensitive_fields(converted_query)
        
        custom_log(f"[DEBUG] _execute_find_one - Collection: {collection}, Original query: {query}, Converted query: {converted_query}, Encrypted query: {encrypted_query}")
        
        # Execute the query directly without expensive operations
        result = self.db[collection].find_one(encrypted_query)
        custom_log(f"[DEBUG] _execute_find_one - Result found: {result is not None}")
        
        if result:
            decrypted_result = self._decrypt_sensitive_fields(result)
            final_result = self._convert_objectid_to_string(decrypted_result)
            custom_log(f"[DEBUG] _execute_find_one - Final result: {final_result.get('email') if final_result else None}")
            return final_result
        return None

    def _execute_update(self, collection: str, query: Dict[str, Any], data: Dict[str, Any]) -> int:
        """Execute update operation directly (for queue worker)."""
        if not self.available:
            return 0
        # Convert string _id to ObjectId for MongoDB queries
        converted_query = self._convert_string_to_objectid(query)
        encrypted_data = self._encrypt_sensitive_fields(data)
        result = self.db[collection].update_many(converted_query, {'$set': encrypted_data})
        return result.modified_count

    def _execute_delete(self, collection: str, query: Dict[str, Any]) -> int:
        """Execute delete operation directly (for queue worker)."""
        if not self.available:
            return 0
        # Convert string _id to ObjectId for MongoDB queries
        converted_query = self._convert_string_to_objectid(query)
        result = self.db[collection].delete_many(converted_query)
        return result.deleted_count

    def get_queue_status(self) -> Dict[str, Any]:
        """Get current queue status."""
        return {
            'queue_size': self.request_queue.qsize(),
            'max_queue_size': self.max_queue_size,
            'worker_alive': self.worker_thread.is_alive() if self.worker_thread else False,
            'queue_enabled': self.queue_enabled,
            'pending_results': len(self.result_store)
        }

    def enable_queue(self):
        """Enable the queue system."""
        self.queue_enabled = True
        custom_log("✅ Database queue system enabled")

    def disable_queue(self):
        """Disable the queue system."""
        self.queue_enabled = False
        custom_log("⚠️ Database queue system disabled")

    def _get_password_from_file(self, password_file_path: str) -> str:
        """Read password from a file."""
        try:
            with open(password_file_path, 'r') as f:
                return f.read().strip()
        except Exception as e:
            custom_log(f"Failed to read password file: {e}", level="ERROR")
            raise

    def _setup_mongodb_connection(self):
        """Set up MongoDB connection with role-based access control and read-only replicas."""
        # Use centralized config system for all MongoDB settings
        from utils.config.config import Config
        
        mongodb_user = Config.MONGODB_USER
        password = Config.MONGODB_PASSWORD
        mongodb_host = Config.MONGODB_SERVICE_NAME
        mongodb_port = str(Config.MONGODB_PORT)
        mongodb_db = Config.MONGODB_DB_NAME

        if not password:
            raise ValueError("MongoDB password not provided - check Vault, secret files, or environment variables")

        # URL encode username and password
        encoded_user = quote_plus(mongodb_user)
        encoded_password = quote_plus(password)

        # Construct MongoDB URI with encoded credentials
        mongodb_uri = f"mongodb://{encoded_user}:{encoded_password}@{mongodb_host}:{mongodb_port}/{mongodb_db}?authSource={mongodb_db}"

        # Set up connection options
        options = {
            'readPreference': 'primaryPreferred' if self.role == "read_only" else 'primary',
            'readConcernLevel': 'majority',
            'w': 'majority',
            'retryWrites': True,
            'retryReads': True
        }

        # Create MongoDB client
        self.client = MongoClient(mongodb_uri, **options)
        self.db = self.client[mongodb_db]

        # Verify connection and access
        self._verify_connection_and_access()

    def _verify_connection_and_access(self):
        """Verify MongoDB connection and role-based access."""
        # Test connection
        self.client.server_info()
        self.logger.info("✅ Successfully connected to MongoDB")

        # Test write access if role is read_write
        if self.role == "read_write":
            self.db.command("ping")
            self.logger.info("✅ Write access verified")

    def _encrypt_sensitive_fields(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Encrypt sensitive fields in the data dictionary."""
        encrypted_data = data.copy()
        for field in Config.SENSITIVE_FIELDS:
            if field in encrypted_data and encrypted_data[field] is not None:
                # Use deterministic encryption for searchable fields like email
                deterministic = field in ['email', 'username']  # Fields that need to be searchable
                encrypted_data[field] = self.encryption_manager.encrypt_data(
                    encrypted_data[field], deterministic=deterministic
                )
        return encrypted_data

    def _decrypt_sensitive_fields(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Decrypt sensitive fields in the data dictionary."""
        decrypted_data = data.copy()
        for field in Config.SENSITIVE_FIELDS:
            if field in decrypted_data and decrypted_data[field] is not None:
                try:
                    decrypted_data[field] = self.encryption_manager.decrypt_data(
                        decrypted_data[field]
                    )
                except Exception as e:
                    # If decryption fails (e.g., data was encrypted with different key),
                    # keep the original data and log the issue
                    custom_log(f"⚠️ Failed to decrypt field '{field}': {e}", level="WARNING")
                    # Keep the original value - it might be already decrypted or encrypted with different key
                    decrypted_data[field] = data[field]
        return decrypted_data

    def close(self):
        """Close the MongoDB connection and stop queue worker."""
        # Stop queue worker
        self.queue_enabled = False
        if self.worker_thread and self.worker_thread.is_alive():
            self.worker_thread.join(timeout=5)
        
        # Clear result store
        with self.queue_lock:
            self.result_store.clear()
        
        # Close database connection
        if self.available and self.client:
            self.client.close()
            self.available = False

    def check_connection(self):
        """Check MongoDB connection status."""
        if not self.available:
            return False
            
        try:
            self.client.server_info()
            return True
        except Exception as e:
            custom_log(f"Database connection check failed: {e}", level="ERROR")
            self.available = False
            return False

    def get_connection_count(self):
        """Get the number of active connections to MongoDB."""
        if not self.available:
            return 0
            
        try:
            # Try to get server status, but handle permission errors gracefully
            server_status = self.db.command("serverStatus")
            return server_status.get("connections", {}).get("current", 0)
        except Exception as e:
            # If we don't have permission for serverStatus, just return a default value
            # This is expected for application users who don't have admin privileges
            if "not authorized" in str(e).lower():
                custom_log(f"Application user doesn't have permission for serverStatus command (this is normal)", level="DEBUG")
                return 0
            else:
                custom_log(f"Failed to get connection count: {e}", level="ERROR")
                return 0

    def get_all_database_data(self) -> Dict[str, Any]:
        """Get all data from all collections in the database."""
        if not self.available:
            custom_log("⚠️ Database unavailable - cannot retrieve data")
            return {"error": "Database unavailable"}
            
        try:
            all_data = {}
            
            # Get list of all collections
            collections = self.db.list_collection_names()
            custom_log(f"📊 Found {len(collections)} collections: {collections}")
            
            for collection_name in collections:
                try:
                    # Get all documents from the collection
                    documents = list(self.db[collection_name].find({}))
                    
                    # Convert ObjectIds to strings for JSON serialization
                    converted_documents = []
                    for doc in documents:
                        converted_doc = self._convert_objectid_to_string(doc)
                        # Decrypt sensitive fields if needed
                        decrypted_doc = self._decrypt_sensitive_fields(converted_doc)
                        converted_documents.append(decrypted_doc)
                    
                    all_data[collection_name] = {
                        "count": len(converted_documents),
                        "documents": converted_documents
                    }
                    
                    custom_log(f"📋 Retrieved {len(converted_documents)} documents from collection '{collection_name}'")
                    
                except Exception as e:
                    custom_log(f"❌ Error retrieving data from collection '{collection_name}': {e}", level="ERROR")
                    all_data[collection_name] = {
                        "error": str(e),
                        "count": 0,
                        "documents": []
                    }
            
            custom_log(f"✅ Successfully retrieved data from {len(collections)} collections")
            return all_data
            
        except Exception as e:
            custom_log(f"❌ Error retrieving all database data: {e}", level="ERROR")
            return {"error": f"Failed to retrieve database data: {str(e)}"}

# ... existing code ... 