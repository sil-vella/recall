import os
import importlib.util
from .plugin_base import PluginBase
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

class PluginManager:
    """
    Manages game plugins.
    """

    def __init__(self, game_manager):
        """
        Initialize PluginManager.

        Parameters:
        game_manager (GameManager): The game manager instance.
        logging (tuple): A tuple containing custom_log, log_function_call, and game_play_log.
        """
        self.game_manager = game_manager
        self.plugins = []

    def load_plugins(self, plugin_dir):
        """
        Load plugins from the specified directory.

        Parameters:
        plugin_dir (str): The directory containing the plugins.

        Raises:
        FileNotFoundError: If the specified directory does not exist.
        """
        plugin_dir = os.path.abspath(plugin_dir)  # Ensure the path is absolute
        if not os.path.isdir(plugin_dir):
            raise FileNotFoundError(f"Directory '{plugin_dir}' does not exist.")

        for root, dirs, files in os.walk(plugin_dir):
            if 'index.py' in files:
                plugin_path = os.path.join(root, 'index.py')
                spec = importlib.util.spec_from_file_location('index', plugin_path)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)

                for attr in dir(module):
                    cls = getattr(module, attr)
                    if isinstance(cls, type) and issubclass(cls, PluginBase) and cls is not PluginBase:
                        plugin_instance = cls(self.game_manager)
                        plugin_instance.init()
                        self.plugins.append(plugin_instance)

        # Sort plugins by priority
        self.plugins.sort(key=lambda plugin: plugin.priority(), reverse=True)

    def execute_hook(self, hook_name, *args, **kwargs):
        """
        Execute the specified hook for all loaded plugins.

        Parameters:
        hook_name (str): The name of the hook to execute.
        *args, **kwargs: Additional arguments to pass to the hook.
        """
        for plugin in self.plugins:
            hooks = plugin.hooks()
            if hook_name in hooks:
                hooks[hook_name](*args, **kwargs)