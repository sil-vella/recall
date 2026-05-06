Place sponsor media here (repo: sponsors/media/ — same relative path on the VPS under the site root).

  card_back.png     — playbooks/rop01/12_upload_card_back_image.py → served as https://dutch.mt/sponsors/media/card_back.png
  table_logo.webp   — playbooks/rop01/13_upload_table_logo_image.py → served as https://dutch.mt/sponsors/media/table_logo.webp
  card_back.webp    — playbooks/rop01/12_upload_card_back_image.py → served as https://dutch.mt/sponsors/media/card_back.webp

  card_back/<pack_name>/card_back_<pack_name>.webp
                    — playbooks/rop01/16_upload_card_back_packs.py
                    — served via https://dutch.mt/sponsors/media/card_back.webp?skinId=card_back_<pack_name>

  table_design/<pack_name>/table_design_overlay_<pack_name>.webp
                    — playbooks/rop01/14_upload_table_design_overlays.py
                    — served via https://dutch.mt/sponsors/media/table_design_overlay.webp?skinId=table_design_<pack_name>

  Other images/videos for promotional ads (see sponsors/promotional_ads.yaml) are deployed to /sponsors/adverts/ by
    playbooks/rop01/15_upload_promotional_bundle.py
  (card_back.png and table_logo.png are excluded from that bundle.)
