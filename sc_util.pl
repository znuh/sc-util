#!/usr/bin/perl

use Device::SerialPort;
use Gtk2 '-init';    # auto-initializes Gtk2
use Gtk2::Gdk::Keysyms;
use Glib;
use Gtk2::GladeXML;

my $base_freq;
my $clkdiv;

sub bin_to_hex {
    my $text;
    my $cnt;
    my $res = shift;
    my $buf = shift;

    for ( $cnt = 0 ; $cnt < $res ; $cnt++ ) {
        $text = $text . sprintf( "%02x ", ord( substr( $buf, $cnt, 1 ) ) );
    }

    return $text;
}

sub hex_to_bin {
    my $res;
    my $len;
    my $pos;

    $_ = shift;
    chomp;
    s/\s+//g;

    $len = length($_);

    #print "$_";
    for ( $pos = 0 ; $pos < $len ; $pos += 2 ) {

        #print substr($_,$pos,2);
        $res = $res . chr( hex( substr( $_, $pos, 2 ) ) );
    }

    #@_=split(/\s+/,$_);
    #foreach(@_) {
    #$res = $res.chr(hex($_));
    #}
    return $res;
}

my $dir  = "";
my $term = "";

if ( $ARGV[0] =~ /^fpga:/ ){
    $term = "fpga";
    $base_freq = $ARGV[0];
    $base_freq =~ s/.*?://;
    $base_freq =~ s/:.*//;
    die if $base_freq < 1;
}
elsif ( $ARGV[0] =~ /^phoenix:/ ) {
    $term = "phoenix";
}
else {
    print "usage: $0 <terminal>:<device> (<macro file>)\n";
    print "where terminal is either fpga or phoenix\n";
    print "example: $0 fpga:/dev/ttyUSB0\n";
    exit;
}

$_ = $ARGV[0];
s/.*://;

my $device = tie( *FH, "Device::SerialPort", $_ ) or die "open failed: $_";

$device->databits(8)       or die "databits failed";
$device->stopbits(2)       or die "stopbits failed";
$device->handshake("none") or die "handshake failed";

if ( $term eq "fpga" ) {
    $device->baudrate(38400) or die "baudrate failed";
    $device->parity("none") or die "parity failed";

    #$device->write("\x4f");
}
elsif ( $term eq "phoenix" ) {
    $device->baudrate(9600) or die "baudrate failed";
    $device->parity("even") or die "parity failed";

    #$device->rts_active(0) or die "RTS failed";
}

$device->write_settings or die "cannot write serial settings";

my $w = Glib::IO->add_watch( fileno(FH), 'in', \&read_cb )
  or die "cannot watch device!";

my $glade = Gtk2::GladeXML->new("sc_util.glade");

$glade->signal_autoconnect_from_package('main');

my $hex_in  = $glade->get_widget('entry1');
my $file_in = $glade->get_widget('file_entry');

my $editor    = $glade->get_widget('textview1');
my $scrollwin = $glade->get_widget('scrolledwindow1');
my $buffer    = $editor->get_buffer();

my $freq_label = $glade->get_widget('label1');
$freq_label->set_text("set CLK = ".($base_freq/1000)."MHz / ");

my $clkdiv_val = 0;

if ( $term eq "fpga" ) {
    my $hbox3 = $glade->get_widget('hbox3');
    $hbox3->set( visible => 'true' );
}

my $skip = 0;

my @script = ();
my $script_line;
my $sc_pos;

my $rcvd   = 0;
my $expect = 0;

my %shortcuts;

my @history;
my $history_pos = 0;

if ( defined $ARGV[1] ) {
    open( SC, $ARGV[1] );
    while (<SC>) {
        print $_;
        chomp;
        @_ = split( /=/, $_ );
        $shortcuts{ $_[0] } = hex_to_bin( $_[1] );
    }
    close(SC);
}

$buffer->signal_connect( "insert_text" => text_insertion_done );

Gtk2->main;

# save macros
if ( defined $ARGV[1] ) {
    open( SC, ">$ARGV[1]" );
    foreach $key ( sort ( keys(%shortcuts) ) ) {
        my $val = $shortcuts{$key};
        $val = bin_to_hex( length($val), $val );
        print SC "$key=$val\n";
    }
    close(SC);
}

exit 0;

sub text_insertion_done {
    my $end = $buffer->get_end_iter();
    $editor->scroll_to_iter( $end, 0.0, FALSE, 0.0, 0.0 );
}

sub append {
    my $newdir = shift;
    my $text   = shift;
    my $end    = $buffer->get_end_iter();

    if ( $newdir ne $dir ) {
        $dir  = $newdir;
        $text = "\n$dir $text";
    }

    $buffer->insert( $end, $text );
}

sub glitch {
	my @divs= {};
	my $cnt;
	my $snd_string;
	
	# default clkdiv
	for($cnt=0; $cnt<22; $cnt++) {
		$divs[$cnt]=$clkdiv;
	}
	
	# (cycle,div) tuples
	@_ = split(/,/,shift);
	for($cnt=0; $cnt<=$#_; $cnt+=2) {
		$divs[$_[$cnt]]=$_[$cnt+1];
	}
	
	# prepare cmd buf
	for($cnt=0; $cnt<22; $cnt++) {
		#print "$cnt $divs[$cnt]\n";
		$divs[$cnt] |= 0x60;
		$snd_string = $snd_string . chr($divs[$cnt]);
	}
	$snd_string = $snd_string . chr(0x70);
	
	append( "", "!GLITCH $_\n" );
	
	return $device->write($snd_string);
	
}

sub send_hex {
    my $key  = "";
    my $mult = 1;
    my $bin;

    $_ = shift;

	if (/^glitch/) {
		s/.*?\s+//;
		return glitch($_);
	}

    #print "$_\n";

    if (/=/) {
        $key = $_;
        $key =~ s/=.*//;
        $key =~ s/\s+$//;
        s/.*?=//;
        s/^\s+//;
    }

    if (/\s+x/) {
        $mult = $_;
        $mult =~ s/.*?x//;
        $mult =~ s/^\s+//;
        $mult =~ s/\s+$//;
        s/x.*//;
        s/\s+$//;
    }

    # lookup keyword
    if ( defined $shortcuts{$_} ) {
        $bin = $shortcuts{$_};
    }
    else {
        $bin = hex_to_bin($_);
    }

    # multiply?
    $_ = $bin;
    for ( ; $mult > 1 ; $mult-- ) {
        $bin .= $_;
    }

    return 0 if length($bin) == 0;

    # save?
    if ( length($key) > 0 ) {
        $shortcuts{$key} = $bin;
    }

    append( ">", bin_to_hex( length($bin), $bin ) );

    if ( $term eq "fpga" ) {

        @bin = split( //, $bin );

        $bin = "";

        foreach (@bin) {
            $bin .= "\x80$_";
        }

        $skip = 0;
    }
    elsif ( $term eq "phoenix" ) {
        $skip = length($bin);
    }

    return $device->write($bin);
}

sub read_cb {
    my $res, $buf;

    if ( $skip > 0 ) {
        ( $res, $buf ) = $device->read($skip);
        $skip -= $res;
        return 1;
    }

    ( $res, $buf ) = $device->read(255);

    $rcvd += $res;

    #print "$res $buf\n";

    append( "<", bin_to_hex( $res, $buf ) );

    # TODO: verify response
    if ( $rcvd >= $expect ) {
        $rcvd = 0;
        if ( length( $script[$script_line] ) > 0 ) {
            send_hex( substr( $script[$script_line], 2 ) );
            $expect = ( length( $script[ $script_line + 1 ] ) - 1 ) / 3;
            $script_line += 2;
        }
    }

    return 1;
}

sub entry1_activate_cb {

    if ( send_hex( $hex_in->get_text() ) <= 0 ) {
        return;
    }

    $history_pos = 0;
    $history[0] = $hex_in->get_text();
    chomp( $history[0] );
    unshift( @history, "" );

    $hex_in->set_text("");
}

sub btn_reset_clicked_cb {
    append( ">", "RESET " );
    if ( $term eq "phoenix" ) {
        $device->pulse_rts_on(50);
    }
    elsif ( $term eq "fpga" ) {
        $device->write("\x4b");
        select( undef, undef, undef, 0.2 );
        $device->write("\x4f");
    }
}

sub on_exec_btn_clicked {
    open( IN, $file_in->get_text() ) or print "narf\n";
    @script = <IN>;
    close(IN);
    chomp(@script);

    #print substr($script[0],2);
    #print "\n";
    send_hex( substr( $script[0], 2 ) );
    $expect      = ( length( $script[1] ) - 1 ) / 3;
    $script_line = 2;
    $script_pos  = 0;
}

sub on_entry1_key_press_event {
    my ( $widget, $event ) = @_;
    my $key     = $event->keyval;
    my $lastpos = $history_pos;

    if ( $key == $Gtk2::Gdk::Keysyms{Up} ) {
        $history_pos++;
    }
    elsif ( $key == $Gtk2::Gdk::Keysyms{Down} ) {
        $history_pos--;
    }
    else {
        return;
    }

    if ( $lastpos == 0 ) {
        $history[0] = $hex_in->get_text();
        chomp( $history[0] );
    }

    $history_pos = 0         if $history_pos > $#history;
    $history_pos = $#history if $history_pos < 0;

    $hex_in->set_text( $history[$history_pos] );
    $hex_in->set_position(-1);

    return
      1;    # we did handle that event ourself! don't move the damn focus away!
}

sub window1_destroy_cb {

    #$device->write("\x40") if $term eq "fpga";
    Gtk2->main_quit();
}

sub on_filechooserbutton1_file_set {
    my $widget = shift;

    $file_in->set_text( $widget->get_filename() );
}

sub on_clkdiv_spinbtn_value_changed {
    my $spinbtn    = shift;
    my $val        = int( $spinbtn->get_value() );
    my $freq_label = $glade->get_widget('freq_label');
    my $freq       = $base_freq / $val;
    my $text;

    if ( $freq >= 1000 ) {
        $text = sprintf( "= %2.6f MHz ", $freq / 1000 );
    }
    else {
        $text = sprintf( "= %3.3f kHz ", $freq );
    }
    $text .= "(IO\@" . int( ( $freq * 1000 ) / 372 ) . " baud)";
    $freq_label->set_text($text);

    $clkdiv_val = $val - 1;
    $clkdiv = $clkdiv_val;
    $clkdiv_val += 0x20;
    $clkdiv_val = chr($clkdiv_val);
}

sub on_set_clkdiv_btn_clicked {
    $device->write($clkdiv_val);
}
