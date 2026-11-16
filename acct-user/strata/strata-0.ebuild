# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
inherit acct-user

ACCT_USER_ID=-1
ACCT_USER_GROUPS=( strata video render )
ACCT_USER_HOME=/var/lib/strata
ACCT_USER_COMMENT="Strata inference server"

acct-user_add_deps
