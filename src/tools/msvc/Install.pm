package Install;
#
# Package that provides 'make install' functionality for msvc builds
#
# $PostgreSQL: pgsql/src/tools/msvc/Install.pm,v 1.2 2007/03/17 14:01:01 mha Exp $
#
use strict;
use warnings;
use Carp;
use File::Basename;
use File::Copy;

use Exporter;
our (@ISA,@EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT_OK = qw(Install);

sub Install
{
    $| = 1;

    my $target = shift;

    chdir("../../..") if (-f "../../../configure");
    my $conf = "";
    if (-d "debug")
    {
        $conf = "debug";
    }
    if (-d "release")
    {
        $conf = "release";
    }
    die "Could not find debug or release binaries" if ($conf eq "");
    print "Installing for $conf\n";

    EnsureDirectories($target, 'bin','lib','share','share/timezonesets');

    CopySolutionOutput($conf, $target);
    copy($target . '/lib/libpq.dll', $target . '/bin/libpq.dll');
    CopySetOfFiles('config files', "*.sample", $target . '/share/');
    CopySetOfFiles('timezone names', 'src\timezone\tznames\*.txt',$target . '/share/timezonesets/');
    CopyFiles(
        'timezone sets',
        $target . '/share/timezonesets/',
        'src/timezone/tznames/', 'Default','Australia','India'
    );
    CopySetOfFiles('BKI files', "src\\backend\\catalog\\postgres.*", $target .'/share/');
    CopySetOfFiles('SQL files', "src\\backend\\catalog\\*.sql", $target . '/share/');
    CopyFiles(
        'Information schema data',
        $target . '/share/',
        'src/backend/catalog/', 'sql_features.txt'
    );
    GenerateConversionScript($target);
    GenerateTimezoneFiles($target,$conf);
}

sub EnsureDirectories
{
    my $target = shift;
    mkdir $target unless -d ($target);
    while (my $d = shift)
    {
        mkdir $target . '/' . $d unless -d ($target . '/' . $d);
    }
}

sub CopyFiles
{
    my $what = shift;
    my $target = shift;
    my $basedir = shift;

    print "Copying $what";
    while (my $f = shift)
    {
        print ".";
        $f = $basedir . $f;
        die "No file $f\n" if (!-f $f);
        copy($f, $target . basename($f))
          || croak "Could not copy $f to $target". basename($f). " to $target". basename($f) . "\n";
    }
    print "\n";
}

sub CopySetOfFiles
{
    my $what = shift;
    my $spec = shift;
    my $target = shift;
    my $D;

    print "Copying $what";
    open($D, "dir /b /s $spec |") || croak "Could not list $spec\n";
    while (<$D>)
    {
        chomp;
        next if /regress/; # Skip temporary install in regression subdir
        my $tgt = $target . basename($_);
        print ".";
        copy($_, $tgt) || croak "Could not copy $_: $!\n";
    }
    close($D);
    print "\n";
}

sub CopySolutionOutput
{
    my $conf = shift;
    my $target = shift;
    my $rem = qr{Project\("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}"\) = "([^"]+)"};

    my $sln = read_file("pgsql.sln") || croak "Could not open pgsql.sln\n";
    print "Copying build output files...";
    while ($sln =~ $rem)
    {
        my $pf = $1;
        my $dir;
        my $ext;

        $sln =~ s/$rem//;

        my $proj = read_file("$pf.vcproj") || croak "Could not open $pf.vcproj\n";
        if ($proj !~ qr{ConfigurationType="([^"]+)"})
        {
            croak "Could not parse $pf.vcproj\n";
        }
        if ($1 == 1)
        {
            $dir = "bin";
            $ext = "exe";
        }
        elsif ($1 == 2)
        {
            $dir = "lib";
            $ext = "dll";
        }
        else
        {

            # Static lib, such as libpgport, only used internally during build, don't install
            next;
        }
        copy("$conf\\$pf\\$pf.$ext","$target\\$dir\\$pf.$ext") || croak "Could not copy $pf.$ext\n";
        print ".";
    }
    print "\n";
}

sub GenerateConversionScript
{
    my $target = shift;
    my $sql = "";
    my $F;

    print "Generating conversion proc script...";
    my $mf = read_file('src/backend/utils/mb/conversion_procs/Makefile');
    $mf =~ s{\\\s*[\r\n]+}{}mg;
    $mf =~ /^CONVERSIONS\s*=\s*(.*)$/m
      || die "Could not find CONVERSIONS line in conversions Makefile\n";
    my @pieces = split /\s+/,$1;
    while ($#pieces > 0)
    {
        my $name = shift @pieces;
        my $se = shift @pieces;
        my $de = shift @pieces;
        my $func = shift @pieces;
        my $obj = shift @pieces;
        $sql .= "-- $se --> $de\n";
        $sql .=
"CREATE OR REPLACE FUNCTION $func (INTEGER, INTEGER, CSTRING, INTERNAL, INTEGER) RETURNS VOID AS '\$libdir/$obj', '$func' LANGUAGE C STRICT;\n";
        $sql .= "DROP CONVERSION pg_catalog.$name;\n";
        $sql .= "CREATE DEFAULT CONVERSION pg_catalog.$name FOR '$se' TO '$de' FROM $func;\n";
    }
    open($F,">$target/share/conversion_create.sql")
      || die "Could not write to conversion_create.sql\n";
    print $F $sql;
    close($F);
    print "\n";
}

sub GenerateTimezoneFiles
{
    my $target = shift;
    my $conf = shift;
    my $mf = read_file("src/timezone/Makefile");
    $mf =~ s{\\\s*[\r\n]+}{}mg;
    $mf =~ /^TZDATA\s*:?=\s*(.*)$/m || die "Could not find TZDATA row in timezone makefile\n";
    my @tzfiles = split /\s+/,$1;
    unshift @tzfiles,'';
    print "Generating timezone files...";
    system("$conf\\zic\\zic -d $target/share/timezone " . join(" src/timezone/data/", @tzfiles));
    print "\n";
}

sub read_file
{
    my $filename = shift;
    my $F;
    my $t = $/;

    undef $/;
    open($F, $filename) || die "Could not open file $filename\n";
    my $txt = <$F>;
    close($F);
    $/ = $t;

    return $txt;
}

1;