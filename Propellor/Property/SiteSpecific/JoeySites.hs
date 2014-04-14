-- | Specific configuation for Joey Hess's sites. Probably not useful to
-- others except as an example.

module Propellor.Property.SiteSpecific.JoeySites where

import Propellor
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Gpg as Gpg
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.Git as Git
import qualified Propellor.Property.Service as Service
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Obnam as Obnam
import qualified Propellor.Property.Apache as Apache
import Utility.SafeCommand

oldUseNetShellBox :: Property
oldUseNetShellBox = check (not <$> Apt.isInstalled "oldusenet") $
	propertyList ("olduse.net shellbox")
		[ Apt.installed (words "build-essential devscripts debhelper git libncursesw5-dev libpcre3-dev pkg-config bison libicu-dev libidn11-dev libcanlock2-dev libuu-dev ghc libghc-strptime-dev libghc-hamlet-dev libghc-ifelse-dev libghc-hxt-dev libghc-utf8-string-dev libghc-missingh-dev libghc-sha-dev")
			`describe` "olduse.net build deps"
		, scriptProperty
			[ "rm -rf /root/tmp/oldusenet" -- idenpotency
			, "git clone git://olduse.net/ /root/tmp/oldusenet/source"
			, "cd /root/tmp/oldusenet/source/"
			, "dpkg-buildpackage -us -uc"
			, "dpkg -i ../oldusenet*.deb || true"
			, "apt-get -fy install" -- dependencies
			, "rm -rf /root/tmp/oldusenet"
			] `describe` "olduse.net built"
		]

kgbServer :: Property
kgbServer = withOS desc $ \o -> case o of
	(Just (System (Debian Unstable) _)) ->
		ensureProperty $ propertyList desc
			[ Apt.serviceInstalledRunning "kgb-bot"
			, File.hasPrivContent "/etc/kgb-bot/kgb.conf"
				`onChange` Service.restarted "kgb-bot"
			, "/etc/default/kgb-bot" `File.containsLine` "BOT_ENABLED=1"
				`describe` "kgb bot enabled"
				`onChange` Service.running "kgb-bot"
			]
	_ -> error "kgb server needs Debian unstable (for kgb-bot 1.31+)"
  where
	desc = "kgb.kitenet.net setup"

-- git.kitenet.net and git.joeyh.name
gitServer :: [Host] -> Property
gitServer hosts = propertyList "git.kitenet.net setup"
	[ Obnam.backup "/srv/git" "33 3 * * *"
		[ "--repository=sftp://2318@usw-s002.rsync.net/~/git.kitenet.net"
		, "--encrypt-with=1B169BE1"
		, "--client-name=wren"
		] Obnam.OnlyClient
		`requires` Gpg.keyImported "1B169BE1" "root"
		`requires` Ssh.keyImported SshRsa "root"
		`requires` Ssh.knownHost hosts "usw-s002.rsync.net" "root"
		`requires` Ssh.authorizedKeys "family"
		`requires` User.accountFor "family"
	, Apt.installed ["git", "rsync", "kgb-client-git", "gitweb"]
	, Apt.installedBackport ["git-annex"]
	, File.hasPrivContentExposed "/etc/kgb-bot/kgb-client.conf"
	, toProp $ Git.daemonRunning "/srv/git"
	, "/etc/gitweb.conf" `File.containsLines`
		[ "$projectroot = '/srv/git';"
		, "@git_base_url_list = ('git://git.kitenet.net', 'http://git.kitenet.net/git', 'https://git.kitenet.net/git', 'ssh://git.kitenet.net/srv/git');"
		, "# disable snapshot download; overloads server"
		, "$feature{'snapshot'}{'default'} = [];"
		]
		`describe` "gitweb configured"
	-- Repos push on to github.
	, Ssh.knownHost hosts "github.com" "joey"
	-- I keep the website used for gitweb checked into git..
	, Git.cloned "root" "/srv/git/joey/git.kitenet.net.git" "/srv/web/git.kitenet.net" Nothing
	, website "git.kitenet.net"
	, website "git.joeyh.name"
	, toProp $ Apache.modEnabled "cgi"
	]
  where
	website hn = toProp $ Apache.siteEnabled hn $ apachecfg hn True
		[ "  DocumentRoot /srv/web/git.kitenet.net/"
		, "  <Directory /srv/web/git.kitenet.net/>"
		, "    Options Indexes ExecCGI FollowSymlinks"
		, "    AllowOverride None"
		, "    AddHandler cgi-script .cgi"
		, "    DirectoryIndex index.cgi"
		, "  </Directory>"
		, ""
		, "  ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/"
		, "  <Directory /usr/lib/cgi-bin>"
		, "    SetHandler cgi-script"
		, "    Options ExecCGI"
		, "  </Directory>"
		]

type AnnexUUID = String

-- | A website, with files coming from a git-annex repository.
annexWebSite :: [Host] -> Git.RepoUrl -> HostName -> AnnexUUID -> [(String, Git.RepoUrl)] -> Property
annexWebSite hosts origin hn uuid remotes = propertyList (hn ++" website using git-annex")
	[ Git.cloned "joey" origin dir Nothing
		`onChange` setup
	, setupapache
	]
  where
	dir = "/srv/web/" ++ hn
	setup = userScriptProperty "joey" setupscript
		`requires` Ssh.keyImported SshRsa "joey"
		`requires` Ssh.knownHost hosts "turtle.kitenet.net" "joey"
	setupscript = 
		[ "cd " ++ shellEscape dir
		, "git config annex.uuid " ++ shellEscape uuid
		] ++ map addremote remotes ++
		[ "git annex get"
		]
	addremote (name, url) = "git remote add " ++ shellEscape name ++ " " ++ shellEscape url
	setupapache = toProp $ Apache.siteEnabled hn $ apachecfg hn True $ 
		[ "  ServerAlias www."++hn
		, ""
		, "  DocumentRoot /srv/web/"++hn
		, "  <Directory /srv/web/"++hn++">"
		, "    Options FollowSymLinks"
		, "    AllowOverride None"
		, "  </Directory>"
		, "  <Directory /srv/web/"++hn++">"
		, "    Options Indexes FollowSymLinks ExecCGI"
		, "    AllowOverride None"
		, "    Order allow,deny"
		, "    allow from all"
		, "  </Directory>"
		]

apachecfg :: HostName -> Bool -> Apache.ConfigFile -> Apache.ConfigFile
apachecfg hn withssl middle
	| withssl = vhost False ++ vhost True
	| otherwise = vhost False
  where
	vhost ssl = 
		[ "<VirtualHost *:"++show port++">"
		, "  ServerAdmin grue@joeyh.name"
		, "  ServerName "++hn++":"++show port
		]
		++ mainhttpscert ssl
		++ middle ++
		[ ""
		, "  ErrorLog /var/log/apache2/error.log"
		, "  LogLevel warn"
		, "  CustomLog /var/log/apache2/access.log combined"
		, "  ServerSignature On"
		, "  "
		, "  <Directory \"/usr/share/apache2/icons\">"
		, "      Options Indexes MultiViews"
		, "      AllowOverride None"
		, "      Order allow,deny"
		, "      Allow from all"
		, "  </Directory>"
		, "</VirtualHost>"
		]
	  where
		port = if ssl then 443 else 80 :: Int

mainhttpscert :: Bool -> Apache.ConfigFile
mainhttpscert False = []
mainhttpscert True = 
	[ "  SSLEngine on"
	, "  SSLCertificateFile /etc/ssl/certs/web.pem"
	, "  SSLCertificateKeyFile /etc/ssl/private/web.pem"
	, "  SSLCertificateChainFile /etc/ssl/certs/startssl.pem"
	]
		

annexRsyncServer :: Property
annexRsyncServer = combineProperties "rsync server for git-annex autobuilders"
	[ Apt.installed ["rsync"]
	, File.hasPrivContent "/etc/rsyncd.conf"
	, File.hasPrivContent "/etc/rsyncd.secrets"
	, "/etc/default/rsync" `File.containsLine` "RSYNC_ENABLE=true"
			`onChange` Service.running "rsync"
	, endpoint "/srv/web/downloads.kitenet.net/git-annex/autobuild"
	, endpoint "/srv/web/downloads.kitenet.net/git-annex/autobuild/x86_64-apple-mavericks"
	]
  where
	endpoint d = combineProperties ("endpoint " ++ d)
		[ File.dirExists d
		, File.ownerGroup d "joey" "joey"
		]
