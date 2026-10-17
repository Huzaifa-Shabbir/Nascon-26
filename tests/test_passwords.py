from app.passwords import hash_password, verify_password


def test_hash_roundtrip():
    stored = hash_password("Nascon@26")
    assert verify_password("Nascon@26", stored)
    assert not verify_password("nascon@26", stored)


def test_fixed_salt_is_deterministic():
    assert hash_password("x", b"0" * 16) == hash_password("x", b"0" * 16)


def test_malformed_hash_is_rejected():
    assert not verify_password("x", "not-a-hash")
    assert not verify_password("x", "md5$1$00$00")
