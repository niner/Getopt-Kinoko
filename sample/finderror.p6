#!/usr/bin/env perl6

use Getopt::Kinoko;
use Getopt::Kinoko::Exception;

class ErrnoInfo   { ... }
class LocalCache  { ... }
class LocalConfig { ... }
class ListFetcher { ... }
class StdcErrorParser  { ... }
class ErrorInfoPrinter { ... }

enum Align < LEFT RIGHT >;

constant $GITHUB_PUBLIC     = "https://raw.githubusercontent.com/araraloren/PublicConfigRepo/master/finderror/";
constant $FILE_CONFIG       = "config";
constant $FILE_STDCERROR    = "stderrno";
constant $FILE_SYSTEM       = "system";
constant $FILE_SOCKET       = "socket";
constant $CFG_STDCERROR     = "STDC_ERROR_URL";
constant $CFG_SYSTEM        = "WIN32_SYSTEM_URL";
constant $CFG_SOCKET        = "WIN32_SOCKET_URL";
constant $CFG_SYS_INCLUDE   = "SYSTEM_INCLUDE";
constant $CFG_STDC_HEADER   = "STDC_ERROR_HEADER";
constant $CFG_FETCH_TOOL    = "FETCH_TOOL";
constant $FE_VERSION        = "0.0.1";

&finderror();

sub finderror() {
    my OptionSet ($opts, $config, $update, $find, $list);

    $opts.=new;
    $opts.insert-normal("h|help=b;v|version=b;");

    $config = $opts.deep-clone;
    $config.append-options("l|list=b;s|set=s;");
    $config.insert-front(&getFrontCheckCallback("config"));

    $opts.insert-multi("c|stdc-errno=b;1|win32-system-error=b;2|win32-socket-error=b;");

    $update = $opts.deep-clone;
    $update.push-option("command=s");
    $update.insert-front(&getFrontCheckCallback("update"));

    $opts. push-option("t|table-format=b");
    $opts.insert-multi("no-error=b;no-comment=b;no-number=b;");
    $opts.insert-multi("l|left=b;r|right=b;");
    $opts. push-option("indent=i", 2);

    ($list, $find) = ($opts, $opts.deep-clone);
    $list.insert-front(&getFrontCheckCallback("list"));
    $find.append-options("e|error=b;m|comment=b;n|number=b;");
    $find.push-option("r|regex=b;");
    $find.push-option("i|ignore-case=b;");
    $find.insert-front(&getFrontCheckCallback("find"));

    my Getopt $getopt .= new(:gnu-style);

    $getopt.push("update", $update).push("list", $list);
    $getopt.push("config", $config).push("find", $find);

    &main($getopt.parse(), $getopt);
}

sub getFrontCheckCallback(Str $name) {
	sub check(Argument $arg) {
		if ~$arg.value ne $name {
			X::Kinoko::Fail.new().throw();
		}
 	}
	return &check;
}

# @args => [operator { find | list | update | config}, [options ... ], ... args ...]
# [... args ...] => [hexadecimal decimal string]
sub main(@args, Getopt \getopt) {
    my ($op, $opts) = (getopt.current, getopt{getopt.current});

    if $op eq "" || $op !(elem) < find list update config > {
        &printHelpMessage(getopt, "");
        exit 1;
    }
    if $opts{'version'} {
        &printVersion();
        exit(0) unless $opts{'help'};
    }
    if $opts{'help'} {
        &printHelpMessage(getopt, $op);
        exit(0);
    }

    @args.shift; # ignore fist operator argument

    LocalConfig.getInstance.synchronizationConfig();

    my $ok = False;

    $ok = do given $op {
        when "config" {
            &finderror_doConfig($opts);
        }
        when "find" {
            &printHelpMessage(getopt, "find") if +@args == 0;
            &finderror_doFind($opts, @args);
        }
        when "list" {
            &finderror_doList($opts);
        }
        when "update" {
            &finderror_doUpdate($opts);
        }
        default {
            &printHelpMessage(getopt, "");
        }
    }
    &printHelpMessage(getopt, $op) unless $ok;
}

sub finderror_doConfig(OptionSet \opts) {
    if opts{'list'} {
        my @print;
        @print.push(["Key", "Value"]);
        for LocalConfig.getInstance.configs.kv -> $k, $v {
            @print.push([$k, $v]);
        }
        ErrorInfoPrinter.new(
          table-format  => True,
          indent        => 4,
          align         => Align::LEFT
        ).print(@print);
    }
    elsif opts.has-value('set') {
        if opts{'set'} ~~ /$<key> = (<-[\=]>+) \= $<value> = (.*)/ {
            LocalConfig.getInstance.set($<key>.Str, $<value>.Str);
            LocalConfig.getInstance.updateConfig;
        }
        else {
            die "set argument format error: --set \"key=value\"";
        }
    }
    else {
        return False;
    }
    return True;
}

sub finderror_doFind(OptionSet \opts, @keywords) {
    my @all = [];
    my $localcache = LocalCache.getInstance;

    if opts{'stdc-errno'} {
        @all.append: $localcache.readCache($FILE_STDCERROR);
    }
    if opts{'win32-system-error'} {
        @all.append: $localcache.readCache($FILE_SYSTEM);
    }
    if opts{'win32-socket-error'} {
        @all.append: $localcache.readCache($FILE_SOCKET);
    }
    return False if +@all == 0;
    sub regex-compare(Str \str, @matchs, :$ignore) {
        my $ret = False;
        for @matchs -> $key {
            if $ignore {
                if str ~~ m:i/"{$key}"/ {
                    $ret = !$ret; last;
                }
            }
            else {
                if str ~~ /"{$key}"/ {
                    $ret = !$ret; last;
                }
            }
        }
        $ret;
    }
    my @matched;
    for @all -> $ei {
        if opts{'comment'} || !(opts{'comment'} || opts{'number'} || opts{'errno'}) {
            if (opts{'regex'} && &regex-compare($ei.comment, @keywords, ignore => opts{'ignore-case'}))
                || ($ei.comment (elem) @keywords) {
                @matched.push($ei);next;
            }
        }
        if opts{'errno'} || !(opts{'comment'} || opts{'number'} || opts{'errno'}) {
            if (opts{'regex'} && &regex-compare($ei.error, @keywords, ignore => opts{'ignore-case'}))
                || ($ei.error (elem) @keywords) {
                @matched.push($ei);next;
            }
        }
        if opts{'number'} || !(opts{'comment'} || opts{'number'} || opts{'errno'}) {
            if (opts{'regex'} && &regex-compare($ei.number, @keywords, ignore => opts{'ignore-case'}))
                || ($ei.number (elem) @keywords) {
                @matched.push($ei);next;
            }
        }
    }
    &printResult(opts, @matched);
    True;
}

sub finderror_doUpdate(OptionSet \opts) {
    my $ok = False;
    my \localconfig = LocalConfig.getInstance;
    my (@uris, @files);

    if opts{'stdc-errno'} {
        if localconfig.valueOf($CFG_STDCERROR) eq "" {
            my $ep = StdcErrorParser.new(path => localconfig.valueOf($CFG_SYS_INCLUDE));

            $ep.parse(localconfig.valueOf($CFG_STDC_HEADER));
            LocalCache.getInstance.writeCache($FILE_STDCERROR, $ep.result);
            $ok = True;
        }
        else {
            @uris.push(localconfig.valueOf($CFG_STDCERROR));
            @files.push(&getLocalConfigFilePath($FILE_STDCERROR));
        }
    }
    if opts{'win32-system-error'} {
        @uris.push(localconfig.valueOf($CFG_SYSTEM));
        @files.push(&getLocalConfigFilePath($FILE_SYSTEM));
    }
    if opts{'win32-socket-error'} {
        @uris.push(localconfig.valueOf($CFG_SOCKET));
        @files.push(&getLocalConfigFilePath($FILE_SOCKET));
    }
    if +@uris > 0 {
        my $lf = ListFetcher.new(
            command => opts{'command'},
            tool    => localconfig.valueOf($CFG_FETCH_TOOL)
        );
        for @uris Z @files -> (\url, \file) {
            $lf.fetch(url, file);
        }
        $ok = True;
    }
    promptUser("update ok") if $ok;
    $ok;
}

sub finderror_doList(OptionSet \opts) {
    my @all = [];
    my $localcache = LocalCache.getInstance;

    if opts{'stdc-errno'} {
        @all.append: $localcache.readCache($FILE_STDCERROR);
    }
    if opts{'win32-system-error'} {
        @all.append: $localcache.readCache($FILE_SYSTEM);
    }
    if opts{'win32-socket-error'} {
        @all.append: $localcache.readCache($FILE_SOCKET);
    }
    return False if +@all == 0;
    &printResult(opts, @all);
    True;
}

sub printResult(OptionSet \opts, @errnoinfos) {
    my @output;

    for @errnoinfos -> \ei {
        my @line;
        @line.push(ei.error)    unless opts{'no-errno'};
        @line.push(ei.number)   unless opts{'no-number'};
        @line.push(ei.comment)  unless opts{'no-comment'};
        @output.push(@line);
    }
    my $eip = ErrorInfoPrinter.new(
        table-format  => opts{'table-format'},
        indent        => opts{'indent'},
        align         => do {
            if opts{'left'} {
                Align::LEFT
            }
            elsif opts{'right'} {
                Align::RIGHT
            }
        }
    );
    $eip.print(@output);
}

sub promptUser(Str \str) { str.say; }

sub printHelpMessage(Getopt \getopt, Str \current) {
    my $help = "Usage:\n\n";
    $help ~= $*PROGRAM-NAME ~ " \{update | list | find | config\} [options] *\@keywords" ~ "\n\n"
        if current eq "";
    for getopt.keys.sort() -> $key {
        if current eq $key || current eq "" {
            $help ~= $*PROGRAM-NAME ~ " $key " ~ getopt{$key}.usage ~ "\n\n";
        }
    }
    print $help.chomp;
}

sub printVersion() {
    promptUser: "finderror version: {$FE_VERSION}";
}

sub getLocalConfigPath() {
    my $path = do given $*DISTRO {
        when "mswin32" { "{$*HOME.path}/finderror" }
        default { "{$*HOME.path}/.config/finderror" }
    }
    $path;
}

sub getLocalConfigFilePath(Str \name) {
    %(
        $FILE_CONFIG    => "{getLocalConfigPath()}/finderror.cfg",
        $FILE_SYSTEM    => "{getLocalConfigPath()}/system.ls",
        $FILE_STDCERROR => "{getLocalConfigPath()}/stderrno.ls",
        $FILE_SOCKET    => "{getLocalConfigPath()}/socket.ls",
    ){name};
}

class ErrnoInfo {
    has $.error;
    has $.number;
    has $.comment;
}

class LocalConfig {
    constant @config-key = @[
        $CFG_STDCERROR,
        $CFG_SOCKET,
        $CFG_SYSTEM,
        $CFG_SYS_INCLUDE,
        $CFG_STDC_HEADER,
        $CFG_FETCH_TOOL,
    ];

    sub default-config() {
        my %ret = @config-key Z=> [
            "",
            "{$GITHUB_PUBLIC}socket.ls",
            "{$GITHUB_PUBLIC}system.ls",
            "/usr/include",
            "/usr/include/errno.h",
            "wget"
        ];
        %ret;
    }

    state LocalConfig $instance;

    has %.configs;

    method !new { }

    method getInstance() {
        $instance .= new() unless $instance.defined;
        $instance;
    }

    method synchronizationConfig() {
        self!check-local-path();
        self!read-local-config();
    }

    method updateConfig() {
        self!write-local-config();
    }

    method set(Str \key, Str \value) {
        %!configs{key} = value if key (elem) @config-key;
    }

    method valueOf(Str \name) { %!configs{name}; }

    method !check-local-path() {
        if getLocalConfigPath().IO !~~ :e {
            unless getLocalConfigPath().IO.mkdir() {
                fail "Can not create directory:" ~ getLocalConfigPath();
            }
        }
    }

    method !read-local-config() {
        %!configs = default-config();

        if getLocalConfigFilePath($FILE_CONFIG).IO ~~ :e & :f {
            for getLocalConfigFilePath($FILE_CONFIG).IO.open.lines -> \line {
                if line ~~ /^\[ $<key> = (<-[\]]>+) \]\= $<value> = (.*)/ {
                    %!configs{$<key>.Str} = $<value>.Str if $<key>.Str (elem) @config-key;
                }
            }
        }
        else {
            self!write-local-config();
        }
    }

    method !write-local-config() {
        my $cfg-fh = getLocalConfigFilePath($FILE_CONFIG).IO.open(:w);
        for %!configs.kv -> $k, $v {
            $cfg-fh.say("[{$k}]={$v}");
        }
        $cfg-fh.close();
    }
}

class LocalCache {
    state LocalCache $instance;

    method !new { }

    method getInstance() {
        $instance .= new() unless $instance.defined;
        $instance;
    }

    method readCache(Str \name) {
        self!check-local-cache(name);
        my $eh = getLocalConfigFilePath(name).IO.open;
        my @lines = $eh.lines;
        my @ret;

        while +@lines > 0 {
            my ($e, $c, $n);
            $e = @lines.shift.substr(6).trim;
            $n = @lines.shift.substr(7).trim;
            $c = @lines.shift.substr(8).trim;
            @ret.push(
                ErrnoInfo.new(
                    error   => $e,
                    number  => $n,
                    comment => $c
                )
            );
        }
        @ret;
    }

    method !check-local-cache(Str \name) {
        die "Need execute {$*PROGRAM-NAME} update first"
            if getLocalConfigFilePath(name).IO !~~ :e;
    }

    method cleanCache(Str \name) {
        return if getLocalConfigFilePath(name).IO !~~ :e;
        getLocalConfigFilePath(name).IO.unlink() or
            die "Can not unlink file {getLocalConfigFilePath(name)}: $!";
    }

    multi method writeCache(Str \name, @datas) {
        my $eh = getLocalConfigFilePath(name).IO.open(:w) or
            die "Can not open file {getLocalConfigFilePath(name)}: $!";
        for @datas -> $errno {
            $eh.say("error:{$errno.error}\nnumber:{$errno.number}\ncomment:{$errno.comment}");
        }
        $eh.close();
    }

    multi method writeCache(Str \name, @datas, :$append) {
        my $eh = getLocalConfigFilePath(name).IO.open(:w, :a) or
            die "Can not open file {getLocalConfigFilePath(name)}: $!";
        for @datas -> $errno {
            $eh.say("error:{$errno.error}\nnumber:{$errno.number}\ncomment:{$errno.comment}");
        }
        $eh.close();
    }
}

class StdcErrorParser {
    has %!filter;
    has $.path;
    has @!errnos;

    my regex include {
        <.ws> '#' <.ws> 'include' <.ws>
        \< <.ws> $<header> = (.*) <.ws> \> <.ws>
    }

    my regex edefine {
        <.ws> '#' <.ws> 'define' <.ws>
        $<errno> = ('E'\w*) <.ws>
        $<number> = (\d+) <.ws>
        '/*' <.ws> $<comment> = (.*) <.ws> '*/'
    }

    method !filepath($include) {
        if $include ~~ /^\// {
            return $include;
        }
        return $!path ~ '/' ~ $include;
    }

    method parse(Str $file, $top = True) {
        return if %!filter{$file}:exists;

        %!filter{$file} = 1;

        my \fio = $file.IO;

        $!path = fio.abspath().IO.dirname if $top && !$!path.defined;
        if fio ~~ :e && fio ~~ :f {
            for fio.lines -> $line {

                if $line ~~ /<include>/ {
                    self.parse(self!filepath(~$<include><header>), False);
                }
                elsif $line ~~ /<edefine>/ {
                    @!errnos.push: ErrnoInfo.new(
                        error 	=> $<edefine><errno>.Str,
                        number 	=> $<edefine><number>.Str,
                        comment	=> $<edefine><comment>.Str.trim,
                    );
                }
            }
        }
    }

    method result() { @!errnos; }
}

multi sub shellExec(Str $command) {
    my $proc = shell $command, :out, :err;
    my $outmsg = $proc.out.slurp-rest;
    my $errmsg = $proc.err.slurp-rest;

    return $outmsg ~ "\n" ~ $errmsg;
}

multi sub shellExec(Str $command, :$quite) {
    shell $command ~ " 2>&1 >/dev/null";
}

class ListFetcher {
    has $.tool;
    has $.command;

    constant %COMMAND =  %(
        wget => 'wget -q "%URI%" -O "%FILE%"',
        curl => 'curl -s "%URI%" -o "%FILE%"',
        axel => 'axel -q "%URI%" -o "%FILE%"',
    );

    multi method fetch(Str $uri where * ~~ /^'/'|^'./'/, Str $file) {
        $uri.IO.move($file.IO);
    }

    multi method fetch(Str $uri, Str $file, :$quite) {
        my $cmd = self.get-tool;

        $cmd =$cmd.subst("%URI%", $uri);
        $cmd = $cmd.subst("%FILE%", $file);

        try {
            shellExec($cmd, :$quite);
            CATCH {
                default {
                    note "Command '" ~ $cmd ~ "' failed.";
                    ...
                }
            }
        }
    }

    method fetchAndParse(Str $uri, Str $file, :$quite) {
        die "NOT IMPL";
    }

    method get-tool() {
        my $cmd;

        if $!tool eq "wget" | "curl" | "axel" {
            $cmd = %COMMAND{$!tool};
        }
        else {
            $cmd = $!command;
            unless $cmd.index('%URI%') && $cmd.index('%FILE%') {
                die "command error: use %URI% specify uri and %FILE% as ouput file";
            }
        }
        $cmd;
    }
}

class ErrorInfoPrinter {
    has $.table-format;
    has $.align;
    has $.indent;

    method print(@result) {
        my @pt = $!table-format ?? self.tableFormat(@result) !! self.normalFormat(@result);
        promptUser($_) for @pt;
    }

    method normalFormat(@result) {
        my @ret;

        for @result -> $line {
            @ret.push(@$line.join("\t"));
        }
        @ret;
    }

    method tableFormat(@result) {
        my @table;
        my @width;
        my @max-width = [0, 0, 0];

        require Terminal::WCWidth <&wcswidth>;

        for @result -> $line {
            @width.push(@$line.map({wcswidth($_)}));
        }

        for @width -> $line {
            for ^+@$line -> \col_i {
                @max-width[col_i] = $line.[col_i]
                    if $line.[col_i] > @max-width[col_i];
            }
        }
        @max-width = @max-width.map: { $_ + $!indent };
        given $!align {
            when Align::LEFT {
                for @width Z @result -> ($line-width, $line) {
                    my @t;
                    for ^(+@$line - 1) Z @max-width[0 .. * - 2] -> (\col_i, \width) {
                        @t.push($line.[col_i] ~ (" " x (width - $line-width.[col_i])));
                    }
                    @t.push($line.[* - 1]);
                    @table.push(@t);
                }
            }
            when Align::RIGHT {
                for @width Z @result -> ($line-width, $line) {
                    my @t;
                    for ^(+@$line - 1) Z @max-width[0 .. * - 2] -> (\col_i, \width) {
                        @t.push("{" " x (width - @$line-width.[col_i])}{$line.[col_i]}");
                    }
                    @t.push("\t" ~ $line.[* - 1]); # Don't format last column 
                    @table.push(@t);
                }
            }
        }
        my @ret;
        for @table -> $line {
            @ret.push(@$line.join(""));
        }
        @ret;
    }
}
