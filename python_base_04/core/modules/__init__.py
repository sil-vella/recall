"""
Core modules package for the Flask application.
This package contains all the independent functional modules.
"""

__all__ = [
    'BaseModule',
    'CommunicationsModule',
    'WalletModule', 
    'TransactionsModule',
    'UserManagementModule',
    # 'InAppPurchasesModule',  # Not used; web uses Stripe; native Play Billing TBD
] 