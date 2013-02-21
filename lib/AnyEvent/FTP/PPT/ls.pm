package AnyEvent::FTP::PPT::ls;

# ABSTRACT: list file/directory information
# VERSION

# Perl Power Tool - ls(1)

# ------ use/require pragmas
use File::stat;
use Getopt::Std;
use Exporter ();
our @EXPORT_OK = qw( ls );
#use strict;

# ------ partial inline of Stat::lsMode v0.50 code
# (see http://www.plover.com/~mjd/perl/lsMode/
# for the complete module)
 
#
#
# Stat::lsMode
#
# Copyright 1998 M-J. Dominus 
# (mjd-perl-lsmode@plover.com)
#
# You may distribute this module under the same terms as Perl itself.
#
# $Revision: 1.2 $ $Date: 2004/08/05 14:17:43 $

sub ls {
  local @ARGV = @_;

my @perms = qw(--- --x -w- -wx r-- r-x rw- rwx);
my @ftype = qw(. p c ? d ? b ? - ? l ? s ? ? ?);
$ftype[0] = '';

sub format_mode {
  my $mode = shift;
  my %opts = @_;

  my $setids = ($mode & 07000)>>9;
  my @permstrs = @perms[($mode&0700)>>6, ($mode&0070)>>3, $mode&0007];
  my $ftype = $ftype[($mode & 0170000)>>12];
  
  if ($setids) {
    if ($setids & 01) {		# Sticky bit
      $permstrs[2] =~ s/([-x])$/$1 eq 'x' ? 't' : 'T'/e;
    }
    if ($setids & 04) {		# Setuid bit
      $permstrs[0] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
    }
    if ($setids & 02) {		# Setgid bit
      $permstrs[1] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
    }
  }

  join '', $ftype, @permstrs;
}

# ------ define variables
my $Arg = "";		# file/directory name argument from @ARGV
my $ArgCount = 0;	# file/directory argument count
my $Attributes = "";	# File::stat from STDOUT (isatty() kludge)
my %Attributes = ();	# File::stat directory entry attributes
my %DirEntries = ();	# hash of dir entries and stat attributes
my $Getgrgid = "";	# getgrgid() for this platform
my $Getpwuid = "";	# getpwuid() for this platform
my @Dirs = ();		# directories in ARGV
my @Files = ();		# non-directories in ARGV
my $First = 1;		# first directory entry on command line
my $Maxlen = 1;		# longest string we've seen
my $Now = time;		# time we were invoked
my %Options = ();	# option/flag arguments
my $PathSep = "/";	# path separator
			# (someone might want to patch this via
			# File::Spec...)
my $SixMonths =		# long listing time if < 6 months, else year
 60*60*24*(365/2);
my $VERSION = '0.70';	# because we're V7-compatible :)
my $WinSize = "\0" x 8;	# window size buffer
my $TIOCGWINSZ =	# get window size via ioctl()
 0x40087468;		# should be require sys/ioctl.pl,
			# but that won't exist on all platforms
my $WinCols = 0;	# window columns of output
my $WinRows = 0;	# window rows of output
my $Xpixel = 0;		# window start X
my $Ypixel = 0;		# window start Y

# ------ compensate for lack of getpwuid/getgrgid on some platforms
eval { my $dummy = ""; $dummy = (getpwuid(0))[0] };
if ($@) {
	$Getpwuid = sub { return ($_[0], 0); };
	$Getgrgid = sub { return ($_[0], 0); };
} else {
	$Getpwuid = sub { return getpwuid($_[0]); };
	$Getgrgid = sub { return getgrgid($_[0]); };
}

# ------ functions

# ------ get directory entries
sub DirEntries {
	my $Options = shift;	# option arguments hashref
	local *DH;		# directory handle
	my %Attributes = ();	# entry/attributes hash
	my @Entries = ();	# entries in original order
	my $Name = "";		# entry name

	if (!opendir(DH, $_[0]) || exists($Options{'d'})) {
		if (-e $_[0]) {
			closedir(DH) if (defined(DH));
			push(@Entries, $_[0]);
			$Attributes{$_[0]} = stat($_[0]);
			push(@Entries, \%Attributes);
			return @Entries;
		}
		print "pls: can't access '$_[0]': $!\n";
		return ();
	}
	while ($Name = readdir(DH)) {
		next if (!exists($Options->{'a'}) &&
		 $Name =~ m/^\./o);
		push(@Entries, $Name);
		$Attributes{$Name} = stat("$_[0]$PathSep$Name");
	}
	closedir(DH);

	# ------ return list with %Attributes ref at end
	push(@Entries, \%Attributes);
	return @Entries;
}

# ------ format directory entry
sub EntryFormat {
	my $Options = shift;	# ls option arguments
	my $Attributes = shift;	# entry attributes hashref
	my $Entry = shift;	# directory entry name
	my $Blocks = 0;		# block size when otherwise unknown
	my $BlockSize =		# block size in 512-byte units
	 exists($Options->{'k'}) ? 2 : 1;
	my $DateStr = "";	# time/date string
	my $Gid = -1;		# group ID number
	my $Mode = "";		# file mode
	my @Month = (		# file time month abbrev.
		"Jan",
		"Feb",
		"Mar",
		"Apr",
		"May",
		"Jun",
		"Jul",
		"Aug",
		"Sep",
		"Oct",
		"Nov",
		"Dec"
	);
	my $Time = 0;		# file time
	my $Uid = -1;		# user ID number

# ------ for localtime()
my $sec = 0;
my $min = 0;
my $hour = 0;
my $mday = 0;
my $mon = 0;
my $year = 0;
my $wday = 0;
my $yday = 0;
my $isdst = 0;

	if (exists($Options->{'i'})) {
		if (defined($Attributes->{$Entry})) {
#        1         2         3         4         5         6         7
#23456789*123456789*123456789*123456789*123456789*123456789*123456789*
			printf("%10d ", $Attributes->{$Entry}->ino);
		} else {
			print "_________ ";
		}
	}
	if (exists($Options->{'s'})) {
		if (defined($Attributes->{$Entry})) {
			$Blocks = $Attributes->{$Entry}->blocks;
			if ($Blocks eq '') {
				$Blocks = 0;
			}
			printf("%4d ",
			 $Blocks / $BlockSize +
			  (($Blocks % $BlockSize)
			   > 0));
		} else {
			print "____ ";
		}
	}
	if (!exists($Options->{'l'})) {
		print "$Entry\n";
	} else {
		if (!defined($Attributes->{$Entry})) {
			print <<UNDEFSTAT;
__________ ___ ________ ________ ________ ___ __  _____ 
UNDEFSTAT
		} else {
			$Mode =
			 format_mode($Attributes->{$Entry}->mode);
			print "$Mode ";
			#printf("%8o ",
			# $Attributes->{$Entry}->mode);
			printf("%3d ",
			  $Attributes->{$Entry}->nlink);
			if (exists($Options->{'n'})) {
				printf("%-8d ",
				 $Attributes->{$Entry}->uid);
			} else {
				$Uid =
			  &$Getpwuid($Attributes->{$Entry}->uid);
				if (defined($Uid)) {
					printf("%-8s ", $Uid);
				} else {
					printf("%-8d ",
				 $Attributes->{$Entry}->uid);
				}
			}
			if (exists($Options->{'n'})) {
				printf("%-8d ",
				 $Attributes->{$Entry}->gid);
			} else {
				$Gid =
			  &$Getgrgid($Attributes->{$Entry}->gid);
				if (defined($Gid)) {
					printf("%-8s ", $Gid);
				} else {
					printf("%-8d ",
				 $Attributes->{$Entry}->gid);
				}
			}
			if ($Attributes->{$Entry}->mode & 0140000) {
				printf("%9d ",
				 $Attributes->{$Entry}->size);
			} else {
				printf("%4x,%4x ",
				 (($Attributes->{$Entry}->dev
				  & 0xFFFF000) > 16),
				 $Attributes->{$Entry}->dev
				  & 0xFFFF);
			}
			$Time = $Attributes->{$Entry}->mtime;
			if (exists($Options->{'c'})) {
				$Time = $Attributes->{$Entry}->ctime;
			}
			if (exists($Options->{'u'})) {
				$Time = $Attributes->{$Entry}->atime;
			}
			($sec,$min,$hour,$mday,$mon,$year,
			 $wday,$yday,$isdst) =
                         localtime($Time);
			print $Month[$mon];
			if ($mday < 10) {
				print "  $mday ";
			} else {
				print " $mday ";
			}
			if ($Now - $Time <= $SixMonths) {
				printf("%02d:%02d", $hour, $min);
			} else {
				printf(" %04d", $year + 1900);
			}
		}
		print " $Entry\n";
	}
}

# ------ list directory entries, breadth-first
sub List {
	my $Name = shift;	# directory name
	my $Options = shift;	# options/flags hashref
	my $Expand = shift;	# do 1 level of dir expansion,
				# for "ls DIRNAME"
	my $Attributes = "";	# entry attributes hashref
	my $BlockSize =		# block size in 512-byte units
	 exists($Options->{'k'}) ? 2 : 1;
	my $Cols = 0;		# output columns for this List()
	my $Entry = "";		# directory entry
	my @Dirs = ();		# directories from -R and DirEntries
	my $Mask = "";		# sprintf() format/mask
	my $Mylen = 0;		# current entry length
	my $Path = "";		# path for subdirectories
	my $Piece = "";		# piece of entry list
	my @SortedEntries = ();	# sorted entry list
	my $Rows = 0;		# output rows for this List()
	my $Target = 0;		# target element index
	my $TotalBlocks = 0;	# total directory size in blocks
	my $elt = 0;		# element index

	# ------ get directory entries attributes
	$Attributes = pop(@_);

	# ------ precompute max entry length and total size
	foreach (@_) {
		$TotalBlocks +=
		 (!defined($Attributes->{$_}) ||
		  ($Attributes->{$_}->blocks eq '')) ?
		   0: $Attributes->{$_}->blocks;
		$Mylen = length($_);
		if ($Mylen > $Maxlen) {
			$Maxlen = $Mylen;
		}
	}
	$Maxlen += 1;	# account for spaces

	# ------ print directory name if -R
	if (exists($Options->{'R'})) {
		print "$Name:\n";
	}

	# ----- print total in blocks if -s or -l
	if (exists($Options->{'l'}) || exists($Options->{'s'})) {
		print "total $TotalBlocks\n";
	}

	# ------ sort entry list
	@SortedEntries = Order(\%Options, $Attributes, @_);

	# ------ user requested 1 entry/line, long, size, or inode
	if (defined($Options->{'1'}) ||
	 exists($Options->{'l'}) ||
	 exists($Options->{'s'}) ||
	 exists($Options->{'i'})) {
		foreach $Entry (@SortedEntries) {
			EntryFormat(\%Options,
			 $Attributes, $Entry);
		}

	# ------ multi-column output
	} else {

		# ------ compute rows, columns, width mask
		$Cols = int($WinCols / $Maxlen) || 1;
		$Rows = int(($#_+$Cols) / $Cols);
		$Mask = sprintf("%%-%ds ", $Maxlen);
	
		for ($elt = 0; $elt < $Rows * $Cols; $elt++) {
			$Target =  ($elt % $Cols) * $Rows +
			 int(($elt / $Cols));
			$Piece = sprintf($Mask,
			 $Target < ($#SortedEntries + 1) ?
			  $SortedEntries[$Target] : "");
			# don't blank pad to eol of line
			$Piece =~ s/\s+$//
			 if (($elt+1) % $Cols == 0);
			print $Piece;
			print "\n" if (($elt+1) % $Cols == 0);
		}
		print "\n" if (($elt+1) % $Cols == 0);
	}

	# ------ print blank line if -R
	if (exists($Options->{'R'})) {
		print "\n";
	}

	# ------ list subdirectories of this directory
	if (!exists($Options{'d'}) &&
	 ($Expand || exists($Options->{'R'}))) {
		foreach $Entry (Order(\%Options, $Attributes, @_)) {
			next if ($Entry eq "." || $Entry eq "..");
			if (defined($Attributes->{$Entry}) &&
			 $Attributes->{$Entry}->mode & 0040000) {
				$Path = "$Name:  $PathSep$Entry";
				if ($Name =~ m#$PathSep$#) {
					$Path = "$Name:  $Entry";
				}
				@Dirs = DirEntries(\%Options, $Path);
				List($Path, \%Options, 0, @Dirs);
			}
		}
	}
}

# ------ sort file list based on %Options
sub Order {
	my $Options = shift;	# parsed option/flag arguments
	my $Attributes = shift;	# File::stat attributes hashref
	my @Entries = @_;	# directory entry names

	# ------ sort by size, largest first
	if (exists($Options->{'S'})) {
		if (exists($Options->{'r'})) {
			@Entries = sort
			 { $Attributes->{$a}->size <=>
			   $Attributes->{$b}->size }
			 @Entries;
		} else {
			@Entries = sort
			 { $Attributes->{$b}->size <=>
			   $Attributes->{$a}->size }
			 @Entries;
		}

	# ------ sort by time, most recent first
	} elsif (exists($Options->{'t'}) ||
	 exists($Options->{'c'}) ||
	 exists($Options->{'u'})) {
		if (exists($Options->{'r'})) {
			if (exists($Options->{'u'})) {
				@Entries = sort
				 { $Attributes->{$a}->atime <=>
				   $Attributes->{$b}->atime }
				 @Entries;
			} elsif (exists($Options->{'c'})) {
				@Entries = sort
				 { $Attributes->{$a}->ctime <=>
				   $Attributes->{$b}->ctime }
				 @Entries;
			} else {
				@Entries = sort
				 { $Attributes->{$a}->mtime <=>
				   $Attributes->{$b}->mtime }
				 @Entries;
			}
		} else {
			if (exists($Options->{'u'})) {
				@Entries = sort
				 { $Attributes->{$b}->atime <=>
				   $Attributes->{$a}->atime }
				 @Entries;
			} elsif (exists($Options->{'c'})) {
				@Entries = sort
				 { $Attributes->{$b}->ctime <=>
				   $Attributes->{$a}->ctime }
				 @Entries;
			} else {
				@Entries = sort
				 { $Attributes->{$b}->mtime <=>
				   $Attributes->{$a}->mtime }
				 @Entries;
			}
		}

	# ------ sort by name
	} elsif (!exists($Options->{'f'})) {
		if (exists($Options->{'r'})) {
			@Entries = sort { $b cmp $a } @Entries;
		} else {
			@Entries = sort { $a cmp $b } @Entries;
		}
	}

	# ------ return list sorted by options (or unsorted if -f)
	return @Entries;
}

# ------ process arguments
getopts('1ACFLRSTWacdfgiklmnopqrstux', \%Options);

# ------ get (or guess) window size
if (ioctl(STDOUT, $TIOCGWINSZ, $WinSize)) {
	($WinRows, $WinCols, $Xpixel, $Ypixel) = unpack('S4', $WinSize);
} else {
	$WinCols = 80;
}
$Attributes = stat(STDOUT);
if ($Attributes->mode & 0140000) {
	$Options{'1'} = '1';
}

# ------ current directory if no arguments
if ($#ARGV < 0) {
	List('.', \%Options, 0, DirEntries(\%Options, "."));

# ------ named files/directories if arguments
} else {
	$ArgCount = -1;
	foreach $Arg (@ARGV) {
		if (!exists($Options{'d'}) && -d $Arg) {
			$ArgCount++;
			push(@Dirs, $Arg);
		} else {
			$ArgCount += 2;
			push(@Files, $Arg);
		}
	}
	foreach $Arg (@Files) {
		$Attributes{$Arg} = stat($Arg);
	}
	foreach $Arg (Order(\%Options, \%Attributes, @Files)) {
		$First = 0;
		List($Arg, \%Options, 0,
		 DirEntries(\%Options, $Arg));
	}
	foreach $Arg (@Dirs) {
		$Attributes{$Arg} = stat($Arg);
	}
	foreach $Arg (Order(\%Options, \%Attributes, @Dirs)) {
		if (!exists($Options{'R'})) {
			print "\n" if (!$First);
			$First = 0;
			print "$Arg:\n" if ($ArgCount > 0);
		}
		List($Arg, \%Options, 0,
		 DirEntries(\%Options, $Arg));
	}
}

} # end sub ls

1;

__END__

=pod

=head1 SYNOPSIS

 use AnyEvent::FTP::PPT::ls qw( ls );
 
 my $output = ls('-l');

=head1 DESCRIPTION

This is the ls snarked from PPT as a module.  The rest
of this document comes from the original PPT ls documentation.

This programs lists information about files and directories.
If it is invoked without file/directory name arguments,
it lists the contents of the current directory.  
Otherwise, B<ls> lists information about the files and
information about the contents of the directories (but
see B<-d>).  Furthermore, without any option arguments
B<ls> justs lists the names of files and directories.
All files are listed before all directories.
The default sort order is ascending ASCII on filename.

=head2 OPTIONS

The BSD options
'1ACFLRSTWacdfgiklmnopqrstux'
are recognized,
but only '1RSacdfiklnrstu' are implemented:

=over 4

=item -1

List entries 1 per line (default if output is not a tty).

=item -R

Recursively list the contents of all directories, breadth-first.

=item -S

Sort descending by size.

=item -a

List all files (normally files starting with '.' are ignored).

=item -c

Sort by decending last modification time of inode.

=item -d

Do not list directory contents.

=item -f

Do not sort -- list in whatever order files/directories are returned
by the directory read function.

=item -i

List file inode number.  (Doesn't mean much on non-inode systems.)

=item -k

When used with B<-s>, list file/directory size in 1024-byte blocks.

=item -l

Long format listing of mode -- # of links, owner name, group name,
size in bytes, time of last modification, and name.

=item -n

List numeric uid and gid (default on platforms without getpwuid()).

=item -r

Reverse sorting order.

=item -s

List file/directory size in 512-byte blocks.  (May not mean much
on non-Unix systems.)

=item -t

Sort by decending last modification time.

=item -u

Sort by decending last access time.

=back

=head1 ENVIRONMENT

=head1 BUGS

The file metadata from stat() is used, which may not necessarily
mean much on non-Unix systems.  Specifically, the uid, gid, inode,
and block numbers may be meaningless (or less than meaningful
at least).

The B<-l> option does not yet list the major and minor
device numbers for special files, but it does list
the value of the 'dev' field as 2 hex 16-bit words.
Doing this properly would
probably require filesystem type probing.

=head1 AUTHOR

This Perl implementation of I<ls>
was written by Mark Leighton Fisher of Thomson Consumer Electronics,
I<fisherm@tce.com>.

=head1 COPYRIGHT and LICENSE

This program is free and open software. You may use, modify,
distribute, and sell this program (and any modified variants) in any
way you wish, provided you do not restrict others from doing the same.

=cut


