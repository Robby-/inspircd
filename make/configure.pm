#
# InspIRCd -- Internet Relay Chat Daemon
#
#   Copyright (C) 2012 Peter Powell <petpow@saberuk.com>
#   Copyright (C) 2008 Robin Burchell <robin+git@viroteck.net>
#   Copyright (C) 2007-2008 Craig Edwards <craigedwards@brainbox.cc>
#   Copyright (C) 2008 Thomas Stagner <aquanight@inspircd.org>
#   Copyright (C) 2007 Dennis Friis <peavey@inspircd.org>
#
# This file is part of InspIRCd.  InspIRCd is free software: you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, version 2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


package make::configure;

require 5.8.0;

use strict;
use warnings FATAL => qw(all);

use Exporter 'import';
use POSIX;
use make::utilities;
our @EXPORT = qw(get_compiler_info find_compiler test_file test_header promptnumeric dumphash getmodules getrevision getcompilerflags getlinkerflags getdependencies nopedantic yesno showhelp promptstring_s module_installed);

my $revision;

sub get_compiler_info($) {
        my %info = (NAME => shift, VERSION => '0.0');
        my $version = `$info{NAME} -v 2>&1`;
		return (ERROR => 1) if $?;
        if ($version =~ /(?:clang|llvm)\sversion\s(\d+\.\d+)/i) {
                $info{NAME} = 'Clang';
                $info{VERSION} = $1;
                $info{UNSUPPORTED} = $1 lt '3.0';
                $info{REASON} = 'Clang 2.9 and older do not have adequate C++ support.';
        } elsif ($version =~ /gcc\sversion\s(\d+\.\d+)/i) {
                $info{NAME} = 'GCC';
                $info{VERSION} = $1;
                $info{UNSUPPORTED} = $1 lt '4.1';
                $info{REASON} = 'GCC 4.0 and older do not have adequate C++ support.';
        } elsif ($version =~ /(?:icc|icpc)\sversion\s(\d+\.\d+).\d+\s\(gcc\sversion\s(\d+\.\d+).\d+/i) {
                $info{NAME} = 'ICC';
                $info{VERSION} = $1;
                $info{UNSUPPORTED} = $2 lt '4.1';
                $info{REASON} = "ICC $1 (GCC $2 compatibility mode) does not have adequate C++ support."
        }
        return %info;
}  

sub find_compiler {
	foreach my $compiler ('c++', 'g++', 'clang++', 'icpc') {
		return $compiler unless system "$compiler -v > /dev/null 2>&1";
		if ($^O eq 'Darwin') {
			return $compiler unless system "xcrun $compiler -v > /dev/null 2>&1";
		}
	}
	return "";
}

sub test_file($$;$) {
	my ($cc, $file, $args) = @_;
	my $status = 0;
	$args ||= '';
	$status ||= system "$cc -o __test_$file make/test/$file $args >/dev/null 2>&1";
	$status ||= system "./__test_$file >/dev/null 2>&1";
	unlink  "./__test_$file";
	return !$status;
}

sub test_header($$;$) {
	my ($cc, $header, $args) = @_;
	$args ||= '';
	open(CC, "| $cc -E - $args >/dev/null 2>&1") or return 0;
	print CC "#include <$header>";
	close(CC);
	return !$?;
}

sub yesno {
	my ($flag,$prompt) = @_;
	print "$prompt [\e[1;32m$main::config{$flag}\e[0m] -> ";
	chomp(my $tmp = <STDIN>);
	if ($tmp eq "") { $tmp = $main::config{$flag} }
	if (($tmp eq "") || ($tmp =~ /^y/i))
	{
		$main::config{$flag} = "y";
	}
	else
	{
		$main::config{$flag} = "n";
	}
	return;
}

sub getrevision {
	return $revision if defined $revision;
	chomp(my $tags = `git describe --tags 2>/dev/null`);
	$revision = $tags || 'release';
	return $revision;
}

sub getcompilerflags {
	my ($file) = @_;
	open(FLAGS, $file) or return "";
	while (<FLAGS>) {
		if ($_ =~ /^\/\* \$CompileFlags: (.+) \*\/$/) {
			my $x = translate_functions($1, $file);
			next if ($x eq "");
			close(FLAGS);
			return $x;
		}
	}
	close(FLAGS);
	return "";
}

sub getlinkerflags {
	my ($file) = @_;
	open(FLAGS, $file) or return "";
	while (<FLAGS>) {
		if ($_ =~ /^\/\* \$LinkerFlags: (.+) \*\/$/) {
			my $x = translate_functions($1, $file);
			next if ($x eq "");
			close(FLAGS);
			return $x;
		}
	}
	close(FLAGS);
	return "";
}

sub getdependencies {
	my ($file) = @_;
	open(FLAGS, $file) or return "";
	while (<FLAGS>) {
		if ($_ =~ /^\/\* \$ModDep: (.+) \*\/$/) {
			my $x = translate_functions($1, $file);
			next if ($x eq "");
			close(FLAGS);
			return $x;
		}
	}
	close(FLAGS);
	return "";
}

sub nopedantic {
	my ($file) = @_;
	open(FLAGS, $file) or return "";
	while (<FLAGS>) {
		if ($_ =~ /^\/\* \$NoPedantic \*\/$/) {
			my $x = translate_functions($_, $file);
			next if ($x eq "");
			close(FLAGS);
			return 1;
		}
	}
	close(FLAGS);
	return 0;
}

sub getmodules
{
	my ($silent) = @_;

	my $i = 0;

	if (!$silent)
	{
		print "Detecting modules ";
	}

	opendir(DIRHANDLE, "src/modules") or die("WTF, missing src/modules!");
	foreach my $name (sort readdir(DIRHANDLE))
	{
		if ($name =~ /^m_(.+)\.cpp$/)
		{
			my $mod = $1;
			$main::modlist[$i++] = $mod;
			if (!$silent)
			{
				print ".";
			}
		}
	}
	closedir(DIRHANDLE);

	if (!$silent)
	{
		print "\nOk, $i modules.\n";
	}
}

sub promptnumeric($$)
{
	my $continue = 0;
	my ($prompt, $configitem) = @_;
	while (!$continue)
	{
		print "Please enter the maximum $prompt?\n";
		print "[\e[1;32m$main::config{$configitem}\e[0m] -> ";
		chomp(my $var = <STDIN>);
		if ($var eq "")
		{
			$var = $main::config{$configitem};
		}
		if ($var =~ /^\d+$/) {
			# We don't care what the number is, set it and be on our way.
			$main::config{$configitem} = $var;
			$continue = 1;
			print "\n";
		} else {
			print "You must enter a number in this field. Please try again.\n\n";
		}
	}
}

sub module_installed($)
{
	my $module = shift;
	eval("use $module;");
	return !$@;
}

sub promptstring_s($$)
{
	my ($prompt,$default) = @_;
	my $var;
	print "$prompt\n";
	print "[\e[1;32m$default\e[0m] -> ";
	chomp($var = <STDIN>);
	$var = $default if $var eq "";
	print "\n";
	return $var;
}

sub dumphash()
{
	print "\n\e[1;32mPre-build configuration is complete!\e[0m\n\n";
	print "\e[0mBase install path:\e[1;32m\t\t$main::config{BASE_DIR}\e[0m\n";
	print "\e[0mConfig path:\e[1;32m\t\t\t$main::config{CONFIG_DIR}\e[0m\n";
	print "\e[0mData path:\e[1;32m\t\t\t$main::config{DATA_DIR}\e[0m\n";
	print "\e[0mLog path:\e[1;32m\t\t\t$main::config{LOG_DIR}\e[0m\n";
	print "\e[0mModule path:\e[1;32m\t\t\t$main::config{MODULE_DIR}\e[0m\n";
	print "\e[0mCompiler:\e[1;32m\t\t\t$main::cxx{NAME} $main::cxx{VERSION}\e[0m\n";
	print "\e[0mSocket engine:\e[1;32m\t\t\t$main::config{SOCKETENGINE}\e[0m\n";
	print "\e[0mGnuTLS support:\e[1;32m\t\t\t$main::config{USE_GNUTLS}\e[0m\n";
	print "\e[0mOpenSSL support:\e[1;32m\t\t$main::config{USE_OPENSSL}\e[0m\n";
}

sub showhelp
{
	chomp(my $PWD = `pwd`);
	my (@socketengines, $SELIST);
	foreach (<src/socketengines/socketengine_*.cpp>) {
		s/src\/socketengines\/socketengine_(\w+)\.cpp/$1/;
		push(@socketengines, $1);
	}
	$SELIST = join(", ", @socketengines);
	print <<EOH;
Usage: configure [options]

When no options are specified, interactive
configuration is started and you must specify
any required values manually. If one or more
options are specified, non-interactive configuration
is started, and any omitted values are defaulted.

Arguments with a single \"-\" symbol are also allowed.

  --disable-interactive        Sets no options itself, but
                               will disable any interactive prompting.
  --update                     Update makefiles and dependencies
  --clean                      Remove .config.cache file and go interactive
  --enable-gnutls              Enable GnuTLS module [no]
  --enable-openssl             Enable OpenSSL module [no]
  --socketengine=[name]        Sets the socket engine to be used. Possible values are
                               $SELIST.
  --prefix=[directory]         Base directory to install into (if defined,
                               can automatically define config, data, module,
                               log and binary dirs as subdirectories of prefix)
                               [$PWD]
  --config-dir=[directory]     Config file directory for config and SSL certs
                               [$PWD/conf]
  --log-dir=[directory]	       Log file directory for logs
                               [$PWD/logs]
  --data-dir=[directory]       Data directory for variable data, such as the permchannel
                               configuration and the XLine database
                               [$PWD/data]
  --module-dir=[directory]     Modules directory for loadable modules
                               [$PWD/modules]
  --binary-dir=[directory]     Binaries directory for core binary
                               [$PWD/bin]
  --list-extras                Show current status of extra modules
  --enable-extras=[extras]     Enable the specified list of extras
  --disable-extras=[extras]    Disable the specified list of extras
  --help                       Show this help text and exit

EOH
	exit(0);
}

1;

