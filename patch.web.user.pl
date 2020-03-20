#<ACTION> file=>'web/user.pl',hook=>'additional_info'

 if( Adm->chk_privil('SuperAdmin') || Adm->chk_privil('1201') )
 {
    my $db = Db->sql(
        "SELECT b.*, f.ip FROM `pon_bind` b LEFT JOIN `pon_fdb` f ".
        "ON (b.`olt_id`=f.`olt_id` AND b.`llid`=f.`llid` ) WHERE uid=?", $Fuid
    );
    my $tbl = tbl->new( -class=>'pretty width100' );
    while( my %p = $db->line )
    {
        my $info = (Adm->chk_privil('SuperAdmin') || Adm->chk_privil('1202')) ?
            [ url->a('INFO', a=>'ponmon', act=>'edit', bid=>$p{id}, -class=>'nav') ] : '';
        my ($s, $t, $v) = split /\:/, $p{status};
        $tbl->add( $v ? '*' : 'rowoff', [
            [ '',           '',               $info ],
            [ '',           L('IP'),          $p{ip} ],
            [ '',           L('OLT'),         $p{olt_id} ],
            [ '',           L('ONU'),         $p{sn} ],
            [ '',           L('RX'),          $p{rx} ],
            [ '',           L('TX'),          $p{tx} ],
            [ '',           L('Status'),      "$t($s)" ],
            [ '',           L('LAST ERR'),    $p{dereg} ],
        ]);
    }
    # Show WideBox( msg=>$tbl->show, title=>L('PON') );
    push @left, WideBox( msg=>$tbl->show, title=>L('PON') ) if $db->rows; # unshift
 }
