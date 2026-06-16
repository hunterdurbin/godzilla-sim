# Per-card effect test classification ledger

Working ledger for the card-effect test suites in this directory. Each card is
classified into a Tier B template cluster (parameterized suites) or `bespoke`
(hand-written tests in the per-set suites). Classification was produced by
reading every effect script; entries marked here drive the `test_parameters`
tables. If a card's row proves wrong while testing, fix the row AND this file.

Clusters:
- enter_draw — on_enter draws N (optionally discards M), simple condition
- enter_search — on_enter/trigger searches deck/discard with a filter
- mill — trigger mills N with at most a simple follow-up
- destroy_target — destroys opponent battle card(s) by rank cap / scope
- stat_modifier — pure passive getter(s) with a simple condition
- rage_trigger — on_rage_changed family with simple body
- phase_trigger — on_phase_start/end with simple body
- bespoke — everything else → tests live in test_<set>_bespoke*.gd

## EBP01 (78 scripts; 016/053 do not exist)

- enter_draw: 032 (draw 2), 047 (draw 1 discard 1), 055 (draw 1 discard 1)
- enter_search: 019 (deck→play 2 Kamacuras battle, awakening6+from-hand), 034 (discard→play evolution rank≤4 adjacent)
- mill: 002 (invading mill 1; if monster destroy opp rank≤5), 072 (enter, column-gated mill 1; if battle retreat opp TL≤50k)
- destroy_target: 029 (enter zone+adjacent rank≤5), 040 (enter rank≤7 ×1; + invading rage if 5+ monsters discarded), 041 (invading rank≤4 ×1), 065 (enter all in zones 1–5)
- stat_modifier: 014 (engagement≤5; opp turn+awk4+2 battle), 017 (+3000 CP zone 8), 018 (+3000 CP awk4), 023 (+3000 CP rage≥2), 025 (+3000 CP adjacent to monster), 027 (play rank −1/battle card), 028 (engagement≤3 opp turn), 038 (counter immunity 50k; opp turn+awk6), 046 (+3000 CP awk6), 051 (+3000 CP 5+ monsters in discard), 052 (can_be_destroyed=false; awk4+zones1–5+5 monsters discard, caused_by_opponent), 056 (+3000/opp rage; same column opp monster), 062 (+10000 total CP own turn + Destoroyah battle), 067 (+3000 CP awk4), 068 (+3000 CP adjacent), 074 (+20000 CP if "Gravity Beam" in play)
- rage_trigger: 003 (own increase: mill 1, if monster destroy rank≤6), 007 (own increase: if invaded occupied zone reduce opp rage 2), 009 (invading w/ rage≥2: destroy rank≤6), 010 (increase + opp counter start w/ rage≥3: destroy column), 076 (own invasion observed: destroy 1)
- phase_trigger: 001 (counter start own turn: mill 1, if monster +1 rage), 006 (counter start opp turn: destroy column rank≤5)
- bespoke: 004 005 008 011 012 013 015 020 021 022 024 026 030 031 033 035 036 037 039 042 043 044 045 048 049 050 054 057 058 059 060 061 063 064 066 069 070 071 073 075 077 078 079 080

## EBP02 (82 scripts incl. tokens; 063 does not exist)

- enter_draw: (none verified — 013/074 are advance/rage effects, NOT draws)
- enter_search: 058 (revenge: KG monster discard→hand), 062 (revenge: SpaceGodzilla monster discard→hand)
- mill: 014 (enter mill 1; if monster advance to zone 6), 047 (advance: mill 1)
- destroy_target: 004 (enter rank≤6 × strategy count), 018 (enter rank≤monster_zone ×1 if rage≥2)
- stat_modifier: 002 (+5000 TL w/ strategy in play), 011 (+3000 CP rage≥2), 015 (+3000 CP same zone as opp monster), 016 (+5000 CP same column opp monster), 017 (+5000 total CP 4+ battle, own turn), 021 (+3000 field CP adjacent rank≤5), 024 (can_monster_advance/invade=false), 027 (counter immunity 40k awk6+opp strategy), 029 (double opp column CP, opp turn), 031 (+3000 CP w/ 2+ other rank≤5), 033 (+3000 CP awk4), 034 (+3000 CP zone 8), 039 (Biollante battle −3 rank own turn), 041 (+1000 field CP adjacent), 043 (+1000×under field CP adjacent), 045 (+3000 TL × opp rank), 051 (+3000 TL × opp empty zones, 5+ under), 055 (block opp column awk4+3 crystals), 061 (+3000 CP zone 8), 065 (+5000/+10000 CP awk6 3+/5+ under), 066 (+3000 CP awk6), 067 (+5000 CP opp has Godzilla), 072 (+20000 total CP 3+ crystals own turn), 076 (+3000 CP adjacent), T03 (+1000 TL SpaceGodzilla)
- rage_trigger: 001, 005 (increase own turn awk6: opp discard to 3), 008 (increase: destroy rank≤6 same zone), T01 (enter: reduce opp rage 1 — actually enter trigger)
- phase_trigger: 036 (end start own turn: retreat opp TL≤40k if adjacent), 073 (battle played own turn: destroy column rank≤6)
- bespoke: 003 006 007 009 010 012 013 019 020 022 023 025 026 028 030 032 035 037 038 040 042 044 046 048 049 050 052 053 054 056 057 059 060 064 068 069 070 071 074 075 077 078 079 080 T04

## EBP03 (77 scripts; 006/018/024 do not exist)

- enter_draw: 049 (zone8: draw 2 discard 2)
- enter_search: 007 (invading: mill opp-rank, add 1 red/blue battle), 011 (enter: mill opp-rank, add ≤1 red + ≤1 blue), 021 (enter: discard→hand strategy w/ Base), 033 (enter: discard rank5+ battle → search "Space Beam"), 055 (enter: discard Mothra battle → deck top), 070 (counter start own: deck search weapon/mech battle)
- mill: 031 (enter: look top, optional mill 1)
- destroy_target: 020 (counter success w/ Base: rank≤7 ×1), 072 (enter: all opp same column)
- stat_modifier: 022 (+10000 TL w/ Base in play), 045 (+3000 CP adjacent), 056 (+3000 CP same column opp monster), 065 (+3000 CP monster stack≥5), 076 (+5000 TL/card zones 1,5,8, opp turn)
- rage_trigger: 015 (hand battle discarded: reduce opp rage 1), 016 (hand battle discarded: reduce opp rage or gain if opp 0), 019 (counter success w/ Base: +2 rage)
- phase_trigger: 044 (main start own: evolution)
- bespoke: 001 002 003 004 005 008 009 010 012 013 014 017 023 025 026 027 028 029 030 032 034 035 036 037 038 039 040 041 042 043 046 047 048 050 051 052 053 054 057 058 059 060 061 062 063 064 066 067 068 069 071 073 074 075 077 078 079 080

## EBP04 + small sets

- enter_search: EBP04-061 (deck green→discard), EBP04-088 (discard ≤2 non-green→hand), ESD01-002 (invading: deck burst Godzilla 2023→hand)
- mill: EBP04-021 (counter start own: mill 1; if green battle opp discards to 4), EBP04-075 (counter start opp: mill 1; conditional column destroy)
- destroy_target: EBP04-003 (enter rank≤6 ×1, rank1 strategy in play), EBP04-015 (hand discarded + opp rage 0: rank≤6 ×1), EBP04-020 (enter, Base in play: all adjacent), EBP04-034 (enter, 3+ colors discard: rank≤5 ×1), EBP04-035 (enter: lowest zones × color count), EBP04-074 (enter: 1 opp strategy), EBP04-083 (enter: all opp zones 6–8), EBP04-084 (enter: all opp column), ESD01-006 (enter rank≤4 ×1, burst2), ESD01-007 (enter: all opp column, burst3), ESD01-016 (enter: all opp column), ESD02-002 (enter rank≤4 ×1), ESD02-015 (enter: chosen zone + adjacent), EPR-004 (enter: all opp column), EPR-005 (enter: all opp column)
- stat_modifier: EBP04-006 011 016 017 019 023 031 032 036 037 038 044 048 054 056 057 058 060 065 066 068 069 070 071 081 082, ESD01-003 009, ESD02-006 011 012, EFC01-001 004 006
- rage_trigger: ESD01-013 (own increase: destroy rank≤6), ESD02-005 (invading: reduce opp rage 1)
- phase_trigger: EBP04-008 (counter start own awk8: opp discard to 3), ESD01-005 (enter: opp discard to 4), ESD01-015 (enter: opp discard to 2), ESD02-007 008 (main start own: evolution), ESD02-010 (enter if evolved: draw 1), ESD01-004 (invading rage≥2: opp discard to 2)
- bespoke: EBP04-002 004 005 007 009 010 012 013 014 018 022 024 025 026 027 028 029 030 033 039 040 041 042 043 045 046 047 049 050 051 052 053 055 059 062 063 064 067 072 073 077 078 079 080 085 086 087 089 T01, ESD01-010 011 012 014, ESD02-003 004 009 014, EFC01-002 003 005, ESC01-001
- reclassified while writing suites: EBP04-001 → phase_trigger but NOT yet covered (pure on_phase_start counter/opp-turn rage gain) — cover in ebp04 bespoke; EBP04-002 → bespoke (on_opponent_zone_card_destroyed); EBP04-028 → bespoke (mixed card, excluded from stat suites — cover BOTH the get_strategy_hand_rank_modifier getter and the on_battle_card_played discard trigger in ebp04 bespoke); EBP02-001 → phase_trigger (covered in test_cluster_phase_triggers.gd)

NOTE: agent-derived; numbers verified against scripts as rows land in suites.
Misclassifications discovered while writing tests are corrected here.

## Status (2026-06-12): COMPLETE

Every card above is covered: Tier A smoke/consistency (test_effect_smoke.gd,
all scripts), Tier B parameterized clusters (test_cluster_*.gd), Tier C
bespoke (test_esd_bespoke.gd + test_ebp0{1,2,3,4}_bespoke*.gd). Full
tests/unit run: 818 cases, 0 failures. All effect-script `Tested:` headers
flipped to Yes. No effect-script bugs were found during the build-out; one
design note: EBP02-060's on_revenge auto-accepts its "you may" return
(consistent with other auto-accept "may" effects headless).
