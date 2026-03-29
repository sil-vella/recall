Place sponsor media here (repo: sponsors/media/ — same relative path on the VPS under the site root).

  card_back.png     — playbooks/rop01/12_upload_card_back_image.py → served as https://dutch.mt/sponsors/media/card_back.png
  table_logo.png    — playbooks/rop01/13_upload_table_logo_image.py → served as https://dutch.mt/sponsors/media/table_logo.png

  Other images/videos for promotional ads (see sponsors/promotional_ads.yaml) are deployed to /sponsors/adverts/ by
    playbooks/rop01/15_upload_promotional_bundle.py
  (card_back.png and table_logo.png are excluded from that bundle.)
