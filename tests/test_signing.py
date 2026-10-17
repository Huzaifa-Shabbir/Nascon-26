from app.signing import canonical, lots_key, sign


def test_canonical_json_matches_spec():
    assert canonical({"team_id": "t1", "event_type": "goal"}) == '{"event_type":"goal","team_id":"t1"}'


def test_canonical_keeps_non_ascii():
    assert canonical({"name": "Bilāl"}) == '{"name":"Bilāl"}'


def test_signature_vector_1():
    sig = sign("evt-1", {"team_id": "t1", "event_type": "goal"}, salt="demo-salt")
    assert sig == "972a8b558690b19121cc5bea84978f85e8eb15a3735018db36616bab1d7ec501"


def test_lots_vector_2():
    keys = {t: lots_key(42, "lg-1", t) for t in ("t1", "t2", "t3")}
    assert keys["t1"] == "0613316991ce0ac31e88d6003e3ff4d5e21bb072ac5f81b42c0cdc6598453293"
    assert keys["t2"] == "e3e3a14e22727f936e1f288cf5d02a8a9362b1da13c5432725fc10b2c7955dd9"
    assert keys["t3"] == "c8f28e3c2f1eb6c4f636b4f57050e3362a2b39c07fda9b61742a26dd20397028"
    assert sorted(keys, key=keys.get) == ["t1", "t3", "t2"]
