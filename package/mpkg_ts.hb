/* Copyright 2015 Viktor Szakats (vszakats.net/harbour) */

/* Set timestamps for non-generated (repository) files
   before including them in a distributable package.
   For reproducible builds. */

#include "directry.ch"
#include "fileio.ch"

// #define DEBUG

#ifdef DEBUG
   #translate _DEBUG( [<x,...>] ) => OutStd( <x> )
#else
   #translate _DEBUG( [<x,...>] ) =>
#endif

PROCEDURE Main( cMode, cGitRoot, cBinMask )

   LOCAL tmp, aFiles, file, cStdOut, tDate, tDateHEAD
   LOCAL lShallow

   _DEBUG( "mpkg_ts: BEGIN" + hb_eol() )

   cGitRoot := hb_DirSepAdd( hb_defaultValue( cGitRoot, "." ) ) + ".git"
   IF hb_DirExists( cGitRoot )

      _DEBUG( "mpkg_ts: cwd:", hb_cwd() + hb_eol() )
      _DEBUG( "mpkg_ts: git:", cGitRoot + hb_eol() )

      hb_processRun( "git" + ;
         " " + FNameEscape( "--git-dir=" + cGitRoot ) + ;
         " rev-parse --abbrev-ref HEAD",, @cStdOut )

      hb_processRun( "git" + ;
         " " + FNameEscape( "--git-dir=" + cGitRoot ) + ;
         " rev-list " + hb_StrReplace( cStdOut, Chr( 13 ) + Chr( 10 ) ) + ;
         " --count",, @cStdOut )

      lShallow := Val( hb_StrReplace( cStdOut, Chr( 13 ) + Chr( 10 ) ) ) < 2000

      hb_processRun( "git log -1 --format=format:%ci",, @cStdOut )

      tDateHEAD := hb_CToT( cStdOut, "yyyy-mm-dd", "hh:mm:ss" )

      IF Empty( tDateHEAD )
         OutStd( "! mpkg_ts: Error: Failed to obtain last commit timestamp." + hb_eol() )
      ELSE
         tDateHEAD -= ( ( ( iif( SubStr( cStdOut, 21, 1 ) == "-", -1, 1 ) * 60 * ;
                          ( Val( SubStr( cStdOut, 22, 2 ) ) * 60 + ;
                            Val( SubStr( cStdOut, 24, 2 ) ) ) ) - hb_UTCOffset() ) / 86400 )
      ENDIF

      _DEBUG( "mpkg_ts: date HEAD:", tDateHEAD, hb_eol() )

      SWITCH Lower( cMode := hb_defaultValue( cMode, "" ) )
      CASE "pe"

         tmp := hb_DirSepToOS( hb_defaultValue( cBinMask, "" ) )

         OutStd( "! mpkg_ts: Setting build times in executable headers of", tmp + hb_eol() )

         FOR EACH file IN Directory( tmp )
            /* Use a fixed date to change binaries only if their ingredients have changed */
            win_PESetTimestamp( hb_FNameDir( tmp ) + file[ F_NAME ] )
         NEXT

         EXIT

      CASE "ts"

         IF ! Empty( tDateHEAD ) .OR. ! lShallow

            IF lShallow
               OutStd( "! mpkg_ts: Warning: Shallow repository, resorting to last commit timestamp." + hb_eol() )
            ENDIF

            OutStd( "! mpkg_ts: Timestamping repository files..." + hb_eol() )

            FOR EACH tmp IN { ;
               "bin/*.bat", ;
               "bin/*.hb", ;
               "doc/*.txt", ;
               "addons/*.txt", ;
               "contrib/", ;
               "extras/", ;
               "include/", ;
               "src/3rd/", ;
               "tests/" }

               tmp := hb_DirSepToOS( tmp )
               FOR EACH file IN iif( Empty( hb_FNameName( tmp ) ), hb_DirScan( tmp ), Directory( tmp ) )
                  file := hb_FNameDir( tmp ) + file[ F_NAME ]

                  /* NOTE: To extract proper timestamps we need full commit history */
                  IF lShallow
                     hb_FSetDateTime( file, tDateHEAD )
                  ELSE
                     hb_processRun( "git" + ;
                        " " + FNameEscape( "--git-dir=" + cGitRoot ) + ;
                        " log -1 --format=format:%ci" + ;
                        " " + FNameEscape( file ),, @cStdOut )

                     tDate := hb_CToT( cStdOut, "yyyy-mm-dd", "hh:mm:ss" )

                     IF ! Empty( tDate )
                        tDate -= ( ( ( iif( SubStr( cStdOut, 21, 1 ) == "-", -1, 1 ) * 60 * ;
                                     ( Val( SubStr( cStdOut, 22, 2 ) ) * 60 + ;
                                       Val( SubStr( cStdOut, 24, 2 ) ) ) ) - hb_UTCOffset() ) / 86400 )
                        hb_FSetDateTime( file, tDate )
                     ENDIF
                  ENDIF
               NEXT
            NEXT
         ENDIF

         /* Reset directory timestamps to last commit */
         IF ! Empty( tDateHEAD )
            OutStd( "! mpkg_ts: Timestamping directories..." + hb_eol() )
            FOR EACH file IN hb_DirScan( "." + hb_ps(),, "D" ) DESCEND
               IF "D" $ file[ F_ATTR ] .AND. ;
                  !( hb_FNameNameExt( file[ F_NAME ] ) == "." .OR. ;
                     hb_FNameNameExt( file[ F_NAME ] ) == ".." )
                  hb_FSetDateTime( file[ F_NAME ], tDateHEAD )
               ENDIF
            NEXT
         ENDIF

         EXIT

      OTHERWISE
         OutStd( "mpkg_ts: Error: Wrong mode:", "'" + cMode + "'" + hb_eol() )
      ENDSWITCH
   ELSE
      OutStd( "mpkg_ts: Error: Repository not found:", cGitRoot + hb_eol() )
   ENDIF

   _DEBUG( "mpkg_ts: FINISH" + hb_eol() )

   RETURN

STATIC FUNCTION FNameEscape( cFileName )
   RETURN '"' + cFileName + '"'

STATIC FUNCTION win_PESetTimestamp( cFileName, tDateHdr )

   LOCAL lModified := .F.

   LOCAL fhnd, nPEPos, cSignature, tDate, nSections
   LOCAL nPEChecksumPos, nDWORD, cDWORD
   LOCAL tmp, tmp1

   IF Empty( tDateHdr )
      tDateHdr := hb_SToT( "20150101000000" )
   ENDIF

   hb_FGetDateTime( cFileName, @tDate )

   IF ( fhnd := FOpen( cFileName, FO_READWRITE + FO_EXCLUSIVE ) ) != F_ERROR
      IF ( cSignature := hb_FReadLen( fhnd, 2 ) ) == "MZ"
         FSeek( fhnd, 0x003C, FS_SET )
         nPEPos := Bin2W( hb_FReadLen( fhnd, 2 ) ) + ;
                   Bin2W( hb_FReadLen( fhnd, 2 ) ) * 0x10000
         FSeek( fhnd, nPEPos, FS_SET )
         IF !( hb_FReadLen( fhnd, 4 ) == "PE" + hb_BChar( 0 ) + hb_BChar( 0 ) )
            nPEPos := NIL
         ENDIF
      ELSEIF cSignature == "PE" .AND. hb_FReadLen( fhnd, 2 ) == hb_BChar( 0 ) + hb_BChar( 0 )
         nPEPos := 0
      ENDIF
      IF nPEPos != NIL

         FSeek( fhnd, 0x0002, FS_RELATIVE )

         nSections := Bin2W( hb_FReadLen( fhnd, 2 ) )

         nDWORD := Int( ( Max( hb_defaultValue( tDateHdr, hb_SToT() ), hb_SToT( "19700101000000" ) ) - hb_SToT( "19700101000000" ) ) * 86400 )

         IF FSeek( fhnd, nPEPos + 0x0008, FS_SET ) == nPEPos + 0x0008

            cDWORD := hb_BChar( nDWORD % 0x100 ) + ;
                      hb_BChar( nDWORD / 0x100 )
            nDWORD /= 0x10000
            cDWORD += hb_BChar( nDWORD % 0x100 ) + ;
                      hb_BChar( nDWORD / 0x100 )

            IF !( hb_FReadLen( fhnd, 4 ) == cDWORD ) .AND. ;
               FSeek( fhnd, nPEPos + 0x0008, FS_SET ) == nPEPos + 0x0008 .AND. ;
               FWrite( fhnd, cDWORD ) == hb_BLen( cDWORD )
               lModified := .T.
            ENDIF

            IF FSeek( fhnd, nPEPos + 0x0014, FS_SET ) == nPEPos + 0x0014

               nPEPos += 0x0018
               nPEChecksumPos := nPEPos + 0x0040

               IF Bin2W( hb_FReadLen( fhnd, 2 ) ) > 0x0058 .AND. ;
                  FSeek( fhnd, nPEPos + 0x005C, FS_SET ) == nPEPos + 0x005C

                  nPEPos += 0x005C + ;
                            ( ( Bin2W( hb_FReadLen( fhnd, 2 ) ) + ;
                                Bin2W( hb_FReadLen( fhnd, 2 ) ) * 0x10000 ) * 8 ) + 4
                  IF FSeek( fhnd, nPEPos, FS_SET ) == nPEPos
                     tmp1 := nPEPos
                     nPEPos := NIL
                     /* IMAGE_SECTION_HEADERs */
                     FOR tmp := 1 TO nSections
                        FSeek( fhnd, tmp1 + ( tmp - 1 ) * 0x28, FS_SET )
                        /* IMAGE_EXPORT_DIRECTORY */
                        IF hb_FReadLen( fhnd, 8 ) == ".edata" + hb_BChar( 0 ) + hb_BChar( 0 )
                           FSeek( fhnd, 0x000C, FS_RELATIVE )
                           nPEPos := Bin2W( hb_FReadLen( fhnd, 2 ) ) + ;
                                     Bin2W( hb_FReadLen( fhnd, 2 ) ) * 0x10000
                           EXIT
                        ENDIF
                     NEXT
                     IF nPEPos != NIL .AND. ;
                        FSeek( fhnd, nPEPos + 0x0004, FS_SET ) == nPEPos + 0x0004
                        IF !( hb_FReadLen( fhnd, 4 ) == cDWORD ) .AND. ;
                           FSeek( fhnd, nPEPos + 0x0004, FS_SET ) == nPEPos + 0x0004 .AND. ;
                           FWrite( fhnd, cDWORD ) == hb_BLen( cDWORD )
                           lModified := .T.
                        ENDIF
                     ENDIF
                  ENDIF
               ENDIF

               /* Recalculate PE checksum */
               IF lModified
                  tmp := FSeek( fhnd, FS_END, 0 )
                  FSeek( fhnd, FS_SET, 0 )
                  nDWORD := win_PEChecksumCalc( hb_FReadLen( fhnd, tmp ), nPECheckSumPos )
                  IF FSeek( fhnd, nPEChecksumPos ) == nPEChecksumPos
                     cDWORD := hb_BChar( nDWORD % 0x100 ) + ;
                               hb_BChar( nDWORD / 0x100 )
                     nDWORD /= 0x10000
                     cDWORD += hb_BChar( nDWORD % 0x100 ) + ;
                               hb_BChar( nDWORD / 0x100 )
                     FWrite( fhnd, cDWORD )
                  ENDIF
               ENDIF
            ENDIF
         ENDIF
      ENDIF
      FClose( fhnd )
   ENDIF

   IF lModified
      hb_FSetDateTime( cFileName, tDate )
   ENDIF

   RETURN lModified

/* Based on:
      https://stackoverflow.com/questions/6429779/can-anyone-define-the-windows-pe-checksum-algorithm */
STATIC FUNCTION win_PEChecksumCalc( cData, nPECheckSumPos )

   LOCAL nChecksum := 0, nPos

   ++nPECheckSumPos

   FOR nPos := 1 TO hb_BLen( cData ) STEP 4
      IF nPos != nPECheckSumPos
         nChecksum := hb_bitAnd( nChecksum, 0xFFFFFFFF ) + ;
            ( Bin2W( hb_BSubStr( cData, nPos + 0, 2 ) ) + ;
                     Bin2W( hb_BSubStr( cData, nPos + 2, 2 ) ) * 0x10000 ) + ;
            hb_bitShift( nChecksum, -32 )
         IF nChecksum > 0x100000000
            nChecksum := hb_bitAnd( nChecksum, 0xFFFFFFFF ) + hb_bitShift( nChecksum, -32 )
         ENDIF
      ENDIF
   NEXT

   nChecksum := hb_bitAnd( nChecksum, 0xFFFF ) + hb_bitShift( nChecksum, -16 )
   nChecksum := hb_bitAnd( nChecksum + hb_bitShift( nChecksum, -16 ), 0xFFFF )

   RETURN nChecksum + hb_BLen( cData )