# plugin_base.py
from abc import ABC, abstractmethod

class PluginBase(ABC):
    def __init__(self, game_manager):
        self.game_manager = game_manager

    @abstractmethod
    def init(self):
        pass

    @abstractmethod
    def hooks(self):
        """Return a dictionary of hooks and their corresponding methods."""
        pass

    @abstractmethod
    def priority(self):
        """Return the priority of the plugin. Higher numbers indicate higher priority."""
        return 0
