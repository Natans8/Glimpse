"""The generator's declarations agree with each other and with what is committed."""

from __future__ import annotations

import build
import check
import client_globals
import duckdb
import source
import tables


def test_the_committed_toc_is_the_one_the_generator_writes() -> None:
    toc = (source.ROOT / build.ADDON / f"{build.ADDON}.toc").read_text(encoding="utf-8")
    assert toc == build.main_toc(), "run generator/build.py"


def test_the_client_build_is_stated_alike_everywhere() -> None:
    assert check.CLIENT["build"] == source.BUILD == f"9.2.7.{client_globals.BUILD}"
    assert client_globals.TOC == build.INTERFACE


def test_only_m2_models_reach_the_tables() -> None:
    con = duckdb.connect()
    con.execute(f"""
        CREATE SCHEMA {source.SCHEMA};
        CREATE SCHEMA ref;
        CREATE TABLE ref.listfile (fid INTEGER, path VARCHAR);
        CREATE TABLE {source.SCHEMA}."GameObjectDisplayInfo" ("ID" INTEGER, "FileDataID" INTEGER);
        CREATE TABLE {source.SCHEMA}.tdb_gameobject_template (entry INTEGER, displayId INTEGER);
        INSERT INTO ref.listfile VALUES
            (10, 'world/a/chair.m2'), (11, 'world/a/inn.wmo'), (12, 'World/A/Lamp.M2'),
            (13, 'sound/a/creak.ogg');
        INSERT INTO {source.SCHEMA}."GameObjectDisplayInfo"
            VALUES (1, 10), (2, 11), (3, 12), (4, 13);
        INSERT INTO {source.SCHEMA}.tdb_gameobject_template
            VALUES (100, 1), (101, 2), (102, 3), (103, 4);
    """)
    assert tables.object_files(con) == {100: 10, 102: 12}
    assert tables.model_files(con) == {"chair": 10, "lamp": 12}
