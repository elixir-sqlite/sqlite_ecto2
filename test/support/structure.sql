CREATE TABLE "test" (
    "id" INTEGER PRIMARY KEY,
    "name" TEXT
);
CREATE TABLE "schema_migrations" (
    "id" INTEGER PRIMARY KEY,
    "version" TEXT
);
INSERT INTO "schema_migrations" ("version") VALUES (
    "v1"
), (
    "v2"
);
