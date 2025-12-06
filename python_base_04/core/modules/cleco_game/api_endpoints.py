from flask import Blueprint, request, jsonify
from core.managers.jwt_manager import JWTManager
from tools.logger.custom_logging import custom_log

cleco_api = Blueprint('cleco_api', __name__)

# Logging switch for this module
LOGGING_SWITCH = True

@cleco_api.route('/api/auth/validate', methods=['POST'])
def validate_token():
    """Validate JWT token from Dart WebSocket server"""
    custom_log("🔐 API: Token validation request received", level="INFO", isOn=LOGGING_SWITCH)
    custom_log("🔐 API: Blueprint loaded and endpoint hit!", level="INFO", isOn=LOGGING_SWITCH)
    
    try:
        data = request.get_json()
        custom_log(f"📦 API: Request data: {data}", level="DEBUG", isOn=LOGGING_SWITCH)
        
        token = data.get('token')
        
        if not token:
            custom_log("❌ API: No token provided in request", level="WARNING", isOn=LOGGING_SWITCH)
            return jsonify({
                'valid': False,
                'error': 'No token provided'
            }), 400
        
        custom_log(f"🔍 API: Validating token: {token[:20]}...", level="INFO", isOn=LOGGING_SWITCH)
        
        jwt_manager = JWTManager()
        
        try:
            payload = jwt_manager.validate_token(token)
            
            if payload is None:
                custom_log("❌ API: Token validation returned None (invalid/expired/revoked)", level="WARNING", isOn=LOGGING_SWITCH)
                return jsonify({
                    'valid': False,
                    'error': 'Invalid or expired token'
                }), 401
            
            user_id = payload.get('user_id')
            
            custom_log(f"✅ API: Token validation successful for user: {user_id}", level="INFO", isOn=LOGGING_SWITCH)
            
            return jsonify({
                'valid': True,
                'user_id': user_id,
                'payload': payload
            })
        except Exception as e:
            custom_log(f"❌ API: Token validation failed: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                'valid': False,
                'error': 'Invalid or expired token'
            }), 401
            
    except Exception as e:
        custom_log(f"❌ API: Unexpected error in validate_token: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({
            'valid': False,
            'error': str(e)
        }), 500
