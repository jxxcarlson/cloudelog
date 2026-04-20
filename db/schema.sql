\restrict dbmate

-- Dumped from database version 16.13 (Homebrew)
-- Dumped by pg_dump version 16.13 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id text NOT NULL,
    log_id text NOT NULL,
    entry_date date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    quantities double precision[] DEFAULT ARRAY[]::double precision[] NOT NULL,
    descriptions text[] DEFAULT ARRAY[]::text[] NOT NULL
);


--
-- Name: logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logs (
    id text NOT NULL,
    user_id text NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    start_date date DEFAULT CURRENT_DATE NOT NULL,
    metric_names text[] DEFAULT ARRAY[]::text[] NOT NULL,
    metric_units text[] DEFAULT ARRAY[]::text[] NOT NULL,
    CONSTRAINT logs_metrics_nonempty CHECK ((cardinality(metric_names) >= 1)),
    CONSTRAINT logs_metrics_same_length CHECK ((cardinality(metric_names) = cardinality(metric_units)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: streaks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.streaks (
    id integer NOT NULL,
    log_id text NOT NULL,
    start_date date NOT NULL,
    length integer NOT NULL,
    CONSTRAINT streaks_length_check CHECK ((length > 0))
);


--
-- Name: streaks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.streaks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: streaks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.streaks_id_seq OWNED BY public.streaks.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id text NOT NULL,
    email text NOT NULL,
    pw_hash text NOT NULL,
    current_log_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: streaks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streaks ALTER COLUMN id SET DEFAULT nextval('public.streaks_id_seq'::regclass);


--
-- Name: entries entries_log_id_entry_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_log_id_entry_date_key UNIQUE (log_id, entry_date);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: streaks streaks_log_id_start_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streaks
    ADD CONSTRAINT streaks_log_id_start_date_key UNIQUE (log_id, start_date);


--
-- Name: streaks streaks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streaks
    ADD CONSTRAINT streaks_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: entries_log_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX entries_log_date_idx ON public.entries USING btree (log_id, entry_date);


--
-- Name: logs_user_updated_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX logs_user_updated_idx ON public.logs USING btree (user_id, updated_at DESC);


--
-- Name: entries entries_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_log_id_fkey FOREIGN KEY (log_id) REFERENCES public.logs(id) ON DELETE CASCADE;


--
-- Name: logs logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: streaks streaks_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streaks
    ADD CONSTRAINT streaks_log_id_fkey FOREIGN KEY (log_id) REFERENCES public.logs(id) ON DELETE CASCADE;


--
-- Name: users users_current_log_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_current_log_fk FOREIGN KEY (current_log_id) REFERENCES public.logs(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('001'),
    ('002'),
    ('003'),
    ('004');
