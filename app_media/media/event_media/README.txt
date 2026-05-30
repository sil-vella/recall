Special-event media — one directory per event id (matches table_tiers.json special_events[].id).

Layout (example: cards_night):
  event_media/cards_night/cards_night_background.webp
  event_media/cards_night/table_design_overlay_cards_night.webp

Art roles:
  cards_night_background.webp
    - Lobby Special Events carousel backdrop (banner)
    - Game Ended modal hero (end_match_modal.background_image_file)

  table_design_overlay_<event_id>.webp
    - In-game felt table design overlay (same naming as shop table_design/<pack>/)
    - Lobby Special Events felt preview
    - Declarative key: style.overlay_image_file

Optional (same folder, if added later):
  metadata.intro_video_file
  metadata.audio_file

Served locally (Python dev):
  GET {API}/app_media/media/event_media/<event_id>/<filename>

Served on VPS (nginx static under site root):
  https://dutch.reignofplay.com/app_media/media/event_media/<event_id>/<filename>

Upload:
  python playbooks/rop01/18_upload_event_media.py --event cards_night
  python playbooks/rop01/18_upload_event_media.py --all

Placeholder overlays (dev):
  python playbooks/rop01/generate_event_table_design_placeholder_webps.py

Event ids (v1): cards_night, dutch_explorer, the_challenger, dutch_hobbyist, dutch_fan
