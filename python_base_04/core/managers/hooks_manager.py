, function_log, game_play_log, log_function_call

class HooksManager:
    def __init__(self):
        # A dictionary to hold hooks and their callbacks with priorities and optional context
        self.hooks = {
            "app_startup": [],  # Predefined default hook
        }
        @log_function_call
    def register_hook(self, hook_name):
        """
        Register a new hook with the given name.
        :param hook_name: str - The name of the hook to register.
        """
        if hook_name in self.hooks:
            raise ValueError(f"Hook '{hook_name}' is already registered.")
        
        self.hooks[hook_name] = []
        @log_function_call
    def register_hook_callback(self, hook_name, callback, priority=10, context=None):
        """
        Register a callback function to a specific hook with a priority and optional context.
        :param hook_name: str - The name of the hook.
        :param callback: function - The callback function to register.
        :param priority: int - The priority of the callback (lower number = higher priority).
        :param context: str - The optional context (e.g., article type) for the callback.
        """
        if hook_name not in self.hooks:
            raise ValueError(f"Hook '{hook_name}' is not registered.")
        
        # Add the callback to the hook
        self.hooks[hook_name].append({
            "priority": priority,
            "callback": callback,
            "context": context
        })
        
        # Sort callbacks by priority
        self.hooks[hook_name].sort(key=lambda x: x["priority"])

        # Detailed logging of the callback registration
        context_info = f" (context: {context})" if context else ""
        callback_name = callback.__name__ if hasattr(callback, "__name__") else str(callback)
        @log_function_call
    def trigger_hook(self, hook_name, data=None, context=None):
        """
        Trigger a specific hook, executing only callbacks matching the context.
        If the hook doesn't exist, it will be automatically registered first.
        :param hook_name: str - The name of the hook to trigger.
        :param data: Any - Optional data to pass to the callbacks.
        :param context: str - The context to filter callbacks (e.g., article type).
        """
        # Auto-register hook if it doesn't exist
        if hook_name not in self.hooks:
            self.register_hook(hook_name)
        
        for entry in self.hooks[hook_name]:
            # Execute only callbacks matching the context or global callbacks (no context)
            if context is None or entry["context"] == context:
                .")
                entry["callback"](data)

    @log_function_call
    def clear_hook(self, hook_name):
        """
        Clear all callbacks registered to a specific hook.
        :param hook_name: str - The name of the hook to clear.
        """
        if hook_name in self.hooks:
            self.hooks[hook_name] = []
            else:
            @log_function_call
    def dispose(self):
        """
        Dispose of all hooks and their callbacks.
        """
        self.hooks.clear()
        