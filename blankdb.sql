CREATE TABLE revisions
(   revisionid INTEGER PRIMARY KEY
,   edited INTEGER NOT NULL
,   editor TEXT NOT NULL
,   content TEXT NOT NULL
,   lastrevision INTEGER
,   FOREIGN KEY(lastrevision) REFERENCES revisions(revisionid)
);

CREATE TABLE pages
(   pageid INTEGER PRIMARY KEY
,   title TEXT UNIQUE NOT NULL COLLATE NOCASE
,   revision INTEGER NOT NULL UNIQUE
,   FOREIGN KEY(revision) REFERENCES revisions(revisionid)
);

CREATE TABLE links
(   page INTEGER
,   target INTEGER
,   FOREIGN KEY(page) REFERENCES pages(pageid)
,   FOREIGN KEY(target) REFERENCES pages(pageid)
);

insert into revisions values(1, 0, "nobody@localhost", "Nothing here yet", NULL);
insert into pages values(1, "One", 1);
