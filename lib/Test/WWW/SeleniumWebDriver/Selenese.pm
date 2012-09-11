package Test::WWW::SeleniumWebDriver::Selenese;

use Test::More;
use Moose;
use Selenium::Remote::Driver;
use Parse::Selenese;

has 'testbuilder' => (is => 'ro', default => sub { Test::More->builder; });
has 'remote_server_addr' => (is => 'ro', isa => 'Str');
has 'port' => (is => 'ro', isa => 'Int');

has 'base_url' => (is => 'ro', isa => 'Str');
has '_srd' => (is => 'ro', isa => 'Selenium::Remote::Driver', lazy => 1, builder => '_build_srd' );

has 'changed'   => (is => 'rw', isa => 'Bool', default => 0);
has 'wantsource' => (is => 'rw', isa => 'Bool', default => 0);


sub _build_srd {
    my ($self) = @_;
    return Selenium::Remote::Driver->new('remote_server_addr' => $self->remote_server_addr,
                                         'port' => $self->port,
                                         auto_close => 1);
}

sub get_test {
    my ($self, $test) = @_;
    
    if (ref $test) {
        
    } else {
        $test = Parse::Selenese::parse($test);
    }
    return $test;
}

sub convert_command {
    my ($self, $command, $tc) = @_;
    my ($cmd, @values) = @{$command->values};
    my $cmdstr = '';
    my $instr = join ' ',@{$command->values};
    $instr =~ s/\'//g;
    $instr = "'".$instr."'";
    
    if (my $coderef = $self->can($cmd)) {
        $cmdstr = &{$coderef}($self, $tc, $command->values, $instr);
    }
    else {
        $cmdstr = '$tb->todo_skip('.$instr.');'."\n";
    }
    return $cmdstr;
}

sub comment {
    my ($self, $tc, $values, $instr) = @_;
    return '$tb->note('.$instr.');'."\n";
}

sub open {
    my ($self, $tc, $values, $instr) = @_;
    my $url = $self->base_url || $ENV{BASEURL} || $tc->base_url || '';
    return '$srd->get(\''.$url.$values->[1].'\', '.$instr.')'."\n";
}

sub assertHtmlSource {
    my ($self, $tc, $values, $instr) = @_;
    $self->wantsource(1);
    my ($cmp, $val) = $self->locator_to_perl($values->[1]);
    return $cmp.'($source, '.$val.', '. $instr .')'
}

sub locator_to_perl {
    my ($self, $locator) = @_;
    if ($locator =~ /^id=(.*)/) {
        my $val = $1;
        $self->wanttree(1);
        return '$tree->look_down("id" => '._esc_in_q($val).')';
    }
    elsif ($locator =~ /^class=(.*)/) {
        my $val = $1;
        $self->wanttree(1);
        return '$tree->look_down("class" => '._esc_in_q($val).')';
    }
    elsif ($locator =~ /^link=(.*)/) {
        return '$mech->find_link( text => '._esc_in_q($1).')';
    }
    elsif ($locator =~ /^css=(.*)/) {
        my $xp = HTML::Selector::XPath::selector_to_xpath($1);
        $self->wantxpath(1);
        return '$xpath->findnodes('._esc_in_q($xp).')->size';
    }
    elsif ($locator =~ m{^//}) {
        $self->wantxpath(1);
        my $xp = $self->xpath_trim($locator);
        return '$xpath->findnodes('._esc_in_q($xp).')->size';
    }
    elsif ($locator =~ /^regex:(.*)/) {
        return ('like','qr/'._esc_in_regex($locator).'/');
    }
    else {
        $self->wanttree(1);
        return '$tree->look_down("id" => '._esc_in_q($locator).')';
    }
}


sub run {
    my ($self, $test) = @_;
    my $tb = $self->testbuilder;
    my $srd = $self->_srd;
    $test = $self->get_test($test);
    my $source;
    if (ref $test eq 'Parse::Selenese::TestCase') {
        foreach my $command (@{$test->commands}) {
            my ($cmd, $args) = $self->convert_command($command, $test);
            # $cmd = '$tb->diag("Skipping javascript test");'."\n";
            if ($self->wantsource && !$source) {
                $source = $srd->get_page_source();
            }
            # print "cmd: $cmd\n";
            eval $cmd;
            if ($@) {
                die $@.' '.join(' ', @{$command->values})."\n".$cmd;
            }
            if ($self->changed) {
                $self->changed(0);
                $self->wantsource(0);
                $source = undef;
            }
        }
    }
    $srd->quit;
}

=head2 _esc_in_regex

=cut

sub _esc_in_regex {
    my ($str) = @_;
    # print STDERR "str: $str\n\n";
    $str =~ s/^regex\://;
    # $str =~ s/\$\{([^\}]+)\}/$vars{$1}/eg;
    $str =~ s/\//\\\//g;
    $str =~ s/\$/\\\$/g;
    $str = "\\Q$str\\E";
    # $str =~ s/([^A-Za-z\s])/\\$1/g;
    # print STDERR "str: $str\n";
    # $str =~ s/\s/\\s/g;
    return $str;
}


1;

__PACKAGE__->meta->make_immutable;