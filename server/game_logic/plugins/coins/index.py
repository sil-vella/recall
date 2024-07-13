from game_logic.game_management.plugin_base import PluginBase
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log


class ExamplePlugin(PluginBase):
    def init(self):
        custom_log("ExamplePlugin initialized")

    def hooks(self):
        return {
            "on_game_start": self.on_game_start,
            "on_player_join": self.on_player_join,
        }

    def on_game_start(self):
        custom_log("Game has started")

    def on_player_join(self, player):
        custom_log(f"Player {player} has joined the game")

    def priority(self):
        return 10
