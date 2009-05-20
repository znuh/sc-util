#!/usr/bin/perl

use Device::SerialPort;
use Gtk2 '-init'; # auto-initializes Gtk2
use Glib;
use Gtk2::GladeXML;

sub bin_to_hex {
    my $text;
    my $cnt;
    my $res=shift;
    my $buf=shift;

    for($cnt=0;$cnt<$res;$cnt++) {
	$text = $text . sprintf("%02x ",ord(substr($buf,$cnt,1)));
    }

    return $text;    
}

sub hex_to_bin {
    my $res;
    my $len;
    my $pos;
    
    $_=shift;
    chomp;
    s/\s+//g;
    
    $len=length($_);
    #print "$_";
    for($pos=0; $pos<$len; $pos+=2) {
	    #print substr($_,$pos,2);
	    $res = $res.chr(hex(substr($_,$pos,2)));
    }
    
    #@_=split(/\s+/,$_);
    #foreach(@_) {
	#$res = $res.chr(hex($_));
    #}
    return $res;
}

my $dir="";

die "usage: $0 /dev/tty..." if not defined($ARGV[0]);

my $device = tie(*FH, "Device::SerialPort", $ARGV[0]) or die "open failed";
$device->baudrate(9600) or die "baudrate failed";
$device->parity("even") or die "parity failed";
$device->databits(8) or die "databits failed";
$device->stopbits(2) or die "stopbits failed";
$device->handshake("none") or die "handshake failed";
$device->rts_active(0) or die "RTS failed";
$device->write_settings or die "cannot write serial settings";

my $w = Glib::IO->add_watch(fileno(FH), 'in', \&read_cb) or die "cannot watch device!";

my $glade = Gtk2::GladeXML->new("sc_util.glade");

$glade->signal_autoconnect_from_package('main');

my $hex_in = $glade->get_widget('entry1');
my $file_in = $glade->get_widget('file_entry');

my $editor = $glade->get_widget('textview1');
my $buffer = $editor->get_buffer();

my $skip=0;

my @script = ();
my $script_line;
my $sc_pos;

my $rcvd = 0;
my $expect=0;

my %shortcuts;

if (defined $ARGV[1]) {
	open(SC,$ARGV[1]);
	while(<SC>) {
		print $_;
		chomp;
		@_=split(/=/,$_);
		$shortcuts{$_[0]}=hex_to_bin($_[1]);
	}
	close(SC);
}

Gtk2->main;

if (defined $ARGV[1]) {
	open(SC,">$ARGV[1]");
	while (($key, $val) = each %shortcuts) {
		$val=bin_to_hex(length($val),$val);
		print SC "$key=$val\n";
	}
	close(SC);
}

exit 0;

sub append {
    my $newdir=shift;
    my $text = shift;    
    my $end = $buffer->get_end_iter();

    if ($newdir ne $dir) {
	$dir = $newdir;
	$text = "\n$dir $text";
    }

    $buffer->insert($end,$text);
    $end = $buffer->get_end_iter();
    $editor->scroll_to_iter($end,0.0,FALSE,0.0,0.0);
}

sub send_hex {
	my $key="";
	my $mult=1;
	my $bin;
	
	$_ = shift;
	#print "$_\n";
	
	if(/=/) {
		$key=$_;
		$key=~ s/=.*//;
		$key=~ s/\s+$//;
		s/.*?=//;
		s/^\s+//;
	}
	
	if(/x/) {
		$mult=$_;
		$mult=~ s/.*?x//;
		$mult=~ s/^\s+//;
		$mult=~ s/\s+$//;
		s/x.*//;
		s/\s+$//;
	}
	
	$bin = hex_to_bin($_);
	
	# lookup keyword
	if(defined $shortcuts{$_}) {
		$bin = $shortcuts{$_};
	}
	
	# multiply?
	$_=$bin;
	for(;$mult>1;$mult--) {
		$bin.=$_;
	}
	
	# save?
	if(length($key)>0) {
		$shortcuts{$key}=$bin;
	}
	
	$hex_in->set_text("");
	
	append(">",bin_to_hex(length($bin),$bin));
	$device->write($bin);
	$skip=length($bin);
}

sub read_cb {
    my $res, $buf;
    
    if($skip>0) {
	($res,$buf)=$device->read($skip);
	$skip-=$res;
	return 1;
    }
    
    ($res,$buf)=$device->read(255);
    
    $rcvd += $res;
    
    #print "$res $buf\n";    
    
    append("<",bin_to_hex($res,$buf));

	# TODO: verify response
    if($rcvd >= $expect) {
	$rcvd=0;
	if (length($script[$script_line])>0) {
		send_hex(substr($script[$script_line],2));
		$expect = (length($script[$script_line+1])-1)/3;
		$script_line+=2;
	}
    }

    return 1;
}

sub entry1_activate_cb {
	send_hex($hex_in->get_text());
}

sub btn_reset_clicked_cb {
    append(">","RESET ");
    $device->pulse_rts_on(50);
}

sub on_exec_btn_clicked {
	open(IN,$file_in->get_text()) or print "narf\n";
	@script=<IN>;
	close(IN);
	chomp(@script);
	#print substr($script[0],2);
	#print "\n";
	send_hex(substr($script[0],2));
	$expect = (length($script[1])-1)/3;
	$script_line=2;
	$script_pos = 0;
}

sub window1_destroy_cb {
    Gtk2->main_quit();
}
