CREATE TABLE pages
(   pageid INTEGER PRIMARY KEY
,   title TEXT UNIQUE NOT NULL COLLATE NOCASE
);

CREATE TABLE revisions
(   revisionid INTEGER PRIMARY KEY
,   edited INTEGER NOT NULL
,   editor TEXT NOT NULL
,   content TEXT NOT NULL
,   page INTEGER NOT NULL
,   FOREIGN KEY(page) REFERENCES pages(pageid)
);

CREATE TABLE links
(   page INTEGER
,   target INTEGER
,   FOREIGN KEY(page) REFERENCES pages(pageid)
,   FOREIGN KEY(target) REFERENCES pages(pageid)
);

insert into pages values(1, "One");
insert into revisions values(1, 0, "nobody@localhost", "Nothing here yet", 1);
