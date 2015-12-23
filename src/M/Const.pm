package M::Const;

use 5.018;
use strict;
use warnings;
use diagnostics;

use base 'Exporter';

use constant TITLE_PATTERN => qr/^[a-z][a-z0-9]*(?:\/[a-z][a-z0-9]*)*$/i;
use constant USERNAME_PATTERN => qr/^([a-z][a-z0-9]*)(?:#(.*))?$/i;

our @EXPORT = ('TITLE_PATTERN', 'USERNAME_PATTERN');

1;


