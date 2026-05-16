-- Script de création des bases de données QuizUp
-- À exécuter avec un utilisateur PostgreSQL ayant les droits de création de base

-- Créer les bases de données
CREATE DATABASE quizup_profile
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_profile IS 'Base de données pour le Profile Service de QuizUp';

CREATE DATABASE quizup_theme
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_theme IS 'Base de données pour le Theme Service de QuizUp';

CREATE DATABASE quizup_game
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_game IS 'Base de données pour le Game Service de QuizUp';

CREATE DATABASE quizup_identity
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_identity IS 'Base de données pour Identity Service de QuizUp';

CREATE DATABASE quizup_social
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_social IS 'Base de données pour le Social Service de QuizUp';

CREATE DATABASE quizup_leaderboard
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_leaderboard IS 'Base de données pour le Leaderboard Service de QuizUp';

CREATE DATABASE quizup_matchmaking
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE quizup_matchmaking IS 'Base de données pour le Matchmaking Service de QuizUp';

-- Vérifier que les bases ont été créées
SELECT datname FROM pg_database WHERE datname LIKE 'quizup_%' ORDER BY datname;
