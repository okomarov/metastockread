function Out = metastockread(fullpath)

% METASTOCKREAD Read metastock files (symbols index files: master, emaster, xmaster; data files: .dat and .mwd)
%
%   METASTOCKREAD Select with UIGETFILE the metastock file to read.
%                 maetastockread() remembers the last selected file.
%
%   METASTOCKREAD(FULLPATH) Read metastock file FULLPATH to output struct OUT.
%                           The FULLPATH input is a string enclosed in single quotes.
%
%   OUT = metastockread(...)
%       OUT is a "m by 1" NON-scalar structure, where "m" is the # of .dat/.mwd files in the same directory
%       of the symbol index files.
%
%       The (sub)scalar structure has the following fields:
%           - datNum : # of the .dat/.mwd file with the data                           UINT16
%           - symbol : security symbol                                                 CHAR
%           - name   : security name                                                   CHAR
%           - inDate : initial date of the data in datestr format 29 ('yyyy-mm-dd')    CHAR
%           - fiDate : final   date of the data in datestr format 29 ('yyyy-mm-dd')    CHAR
%           - freq   : time freq. of the data I (intraday), D (daily), W, M, Q or Y    CHAR
%           - idFreq : intraday time frequency in minutes                              UINT8
%           - data   : time series data with variable number of fields (columns)       DOUBLE
%
%       The data field columns follow the schema:
%
%       | Date/Time* | Open | High | Low | Close | Volume | OpenInterest |
%       * The date is represented in datenum format. The precision depends on the field idFreq.
%
%       If data has only 5 columns then Volume and OpenInterest columns are absent.
%
% Examples:
%
%     % Read metastock sample data supplied with the submission (unzip the MSdatasample.zip)
%     Out1 = metastockread;                                   % Chose any symbols index file with UIGETFILE
%
%     Out2 = metastockread('MSdatasample directory\Emaster'); % Read in data associated with the Emaster
%     Out3 = metastockread('MSdatasample directory\Xmaster'); % Read in data associated with the Xmaster
%     Out  = [Out2; Out3];                                    % Concatenate results
%
%     whos Out2
%     Name        Size              Bytes  Class     Attributes
%     Out1       255x1            1911591  struct
%
%     Out1(1,1)
%     ans =
%         datNum: 1
%         symbol: 'ASR'
%           name: 'A.S. ROMA'
%         inDate: '2010-01-04'
%         fiDate: '2010-07-09'
%           freq: 'D'
%         idFreq: 0
%           data: [127x7 double]
%
% Additional features:
% - <a href="matlab: web('http://www.mathworks.com/matlabcentral/fileexchange/','-browser')">FEX metastockread page</a>
%
% See also: FREAD, TYPECAST, BITGET, DATESTR, DATENUM

% Author: Oleg Komarov (oleg.komarov@hotmail.it) Copyright 2010-2017
% Tested on R14SP3 (7.1) and on R2016b. In-between compatibility is assumed.
% Platform tested: WIN. If the fcn doesn't work on other platforms please report.

% Remember last opened file
global alreadyOpenedFile

if nargin == 0
    % Select a symbols index file with uigetfile
    [filename, pathname] = uigetfile({'Emaster;Master;Xmaster','Metastock files'},'Load metastock file', alreadyOpenedFile);
    fullpath             = fullfile(pathname, filename);
    alreadyOpenedFile    = fullpath;

    if filename == 0
        disp([char(13) 'The user selected CANCEL.' char(13)])
        alreadyOpenedFile = [];
        return
    end

elseif nargin == 1
    if ischar(fullpath)
        [pathname,filename] = fileparts(fullpath);
    else
        error('metastockread:strFullpath','FULLPATH should be a string.')
    end

else
    error('metastockread:ninput','Too many input arguments.')
end

% Open fid
fid = fopen(fullpath,'r','b');
if fid == -1
    error('metastockread:invalidFullpath','Invalid FULLPATH. File not found.')
end
cleanupFid = onCleanup(@()fclose(fid));

% Read symbols index file: MASTER, EMASTER or XMASTER
switch lower(filename)
    case 'master'
        Out = readMaster(fid);
    case 'emaster'
        Out = readEmaster(fid);
    case 'xmaster'
        Out = readXmaster(fid);
    otherwise
        error('metastockread:namefile','The name of the file should be either MASTER, EMASTER or XMASTER.')
end

numOut = numel(Out);
for ii = 1:numOut
    % Extension of the data files
    if Out(ii).datNum <= 255
        ext = 'DAT';
    else
        ext = 'MWD';
    end
    name       = fullfile(pathname, sprintf('F%d.%s', Out(ii).datNum, ext));
    fid        = fopen(name,'r','b');
    if fid > 0
        cleanupFid = onCleanup(@()fclose(fid));
    end

    % If file not found leave empty data
    if fid == -1
        Out(ii).data = [];
        continue
    end

    % Retrieve the number of records and fields
    fseek(fid,2,'bof');
    numRecs = double(typecast(fread(fid,2,'*uint8'),'uint16'));
    fseek(fid,0,'eof');
    nfields = ftell(fid)/(numRecs*4);

    % Skip header
    fseek(fid,nfields*4,'bof');

    % Retrieve all data at once; the FULL info set would be organized as follows:
    % | Date / Time | Open | High | Low | Close | Volume | OpenInterest |
    Out(ii).data = reshape(mbf2ieee(fread(fid,(numRecs-1)*nfields*4,'*uint8')), nfields, numRecs-1).';

    % Format the date and time into one datenum column (the first)
    [d,m,y] = partNumDate(Out(ii).data(:,1));
    if nfields == 8
        H                 = fix(Out(ii).data(:,2)/1e4);
        M                 = fix(mod(Out(ii).data(:,2)/1e2,1e2));
        Out(ii).data      = Out(ii).data(:,[1 3:8]);
        Out(ii).data(:,1) = datenummx(y,m,d,H,M,0);
    else
        Out(ii).data(:,1) = datenummx(y,m,d);
    end
end
end

% ------------------------------------------------------------------------------------------------------------
% READMASTER  - Read master file
% ------------------------------------------------------------------------------------------------------------
function Out = readMaster(fid)
% Skip header (each record is 53 bytes long)
fseek(fid,53,'bof');
% Read in the whole file
tmp = fread(fid,[53,inf],'*uint8');
% Select and convert useful info
Out = struct('datNum', num2cell(uint16(tmp(1,:).'))         ,... % # of the .dat file with the data
             'symbol', cellstr(char(tmp(37:52,:).'))        ,... % security symbol                    
             'name'  , cellstr(char(tmp(8:23,:).'))         ,... % security name
             'inDate', fmtStrDate(mbf2ieee(tmp(26:29,:)))   ,... % initial date as 'yyyy-mm-dd' (datestr format 29)
             'fiDate', fmtStrDate(mbf2ieee(tmp(30:33,:)))   ,... % final   date as 'yyyy-mm-dd' (datestr format 29)
             'freq'  , cellstr(char(tmp(34,:).'))           ,... % time frequency of the data: I, D, M, W, Q, Y
             'idFreq', num2cell(tmp(35,:).'));                   % intraday time frequency in minutes
end

% ------------------------------------------------------------------------------------------------------------
% READEMASTER - Read emaster file
% ------------------------------------------------------------------------------------------------------------
function Out = readEmaster(fid)
% Skip header (each record is 150 bytes long)
fseek(fid,192,'bof');
% Read in the whole file
tmp = fread(fid,[192,inf],'*uint8');
% Select and convert useful info
Out = struct('datNum'  , num2cell(uint16(tmp(3,:).'))                                 ,...
             'symbol'  , cellstr(char(tmp(12:25,:).'))                                ,...
             'name'    , cellstr(char(tmp(33:48,:).'))                                ,...
             'inDate'  , fmtStrDate(typecast(reshape(tmp(65:68,:),[],1),'single'))    ,...
             'fiDate'  , fmtStrDate(typecast(reshape(tmp(73:76,:),[],1),'single'))    ,...
             'freq'    , cellstr(char(tmp(61,:).'))                                   ,...
             'idFreq'  , num2cell(tmp(63,:).')                                        ,...
             'fullname', cellstr(char(tmp(140:end,:)).'));

end

% ------------------------------------------------------------------------------------------------------------
% READXMASTER - Read xmaster file
% ------------------------------------------------------------------------------------------------------------
function Out = readXmaster(fid)
% Skip header (each record is 192 bytes long)
fseek(fid,150,'bof');
% Read in the whole file
tmp = fread(fid,[150,inf],'*uint8');
% Select and convert useful info
Out = struct('datNum'  , num2cell(typecast(reshape(tmp(66:67,:),[],1),'uint16'))              ,...
             'symbol'  , cellstr(char(tmp(2:15,:).'))                                         ,...
             'fullname', cellstr(char(tmp(17:62,:)).')                                        ,...
             'inDate'  , fmtStrDate(single(typecast(reshape(tmp(109:112,:),[],1),'uint32')))  ,...
             'fiDate'  , fmtStrDate(single(typecast(reshape(tmp(117:120,:),[],1),'uint32')))  ,...
             'freq'    , cellstr(char(tmp(63,:).'))                                           ,...
             'idFreq'  , num2cell(tmp(65,:).'));
end

% ------------------------------------------------------------------------------------------------------------
% MBF2IEEE - Converts MBF to IEEE
% ------------------------------------------------------------------------------------------------------------
function ieee = mbf2ieee(mbf)
% Convert a 32 bit Microsoft Basic Float into a IEEE double of the form (C)YYMMDD (ex: 990123 or 1010123)

% Layout of a MBF:
%
% MBF __________|__Byte 4 __|__Byte 3 __|__Byte 2 __|__Byte 1 __|
% Position bit__| 32 ... 24 | 23 ... 16 | 15 .. . 8 | 7 . . . 0 |
% Value in bit__| EEEE EEEE | XMMM MMMM | MMMM MMMM | MMMM MMMM |
%
% Components:
% X = sign bit
% E = 8 bit exponent
% M = 23 bit mantissa

% Cast into uint32 combining the 4 bytes and convert to double
mbf           = double(typecast(mbf(:),'uint32'));
mantissa_mask = 16777215;                                    % (2^24-1) bottom 24 bits holds the mantissa
exponent_mask = 4278190080;                                    % bitxor(2^32-1,mask1) top 8 bits holds the exponent
mantissa      = bitset  (bitand(mbf,mantissa_mask), 24)    ;   % restore hidden bit
exponent      = bitshift(bitand(mbf,exponent_mask),-24)-152;   % scale exponent
theSign       = double(bitget(mbf,24) == 0)*2 -1 ;             % +1 for zero or positive, -1 for negative
zeroVal       = double(mbf ~= 0) ;                             % 0 for zero values else +1
ieee          = zeroVal .* theSign .* 2.^exponent .* mantissa; % Convert to ieee
end

% ------------------------------------------------------------------------------------------------------------
% FORMATSTRDATE - Converts (C)YYMMDD or YYYYMMDD to datestring format 29
% ------------------------------------------------------------------------------------------------------------
function strdate = fmtStrDate(n)
% Add 1900 if is YYMMDD (ex: 990123 --> 1999-01-23) or CYYMMDD (ex:1010123 --> 2001-01-23) or leave YYYYMMDD (ex: 19990123)
strdate       = sprintf('%d-%02d-%02d',[1900*(~fix(n/1e7)) + fix(n/1e4),fix(mod(n/1e2,1e2)),mod(n,1e2)].');
strdate       = cellstr(reshape(strdate(:),10,[]).');
% Place 'none' if 0
none          = n == 0;
strdate(none) = {'none'};
end

% ------------------------------------------------------------------------------------------------------------
% PARTNUMDATE - Parts (C)YYMMDD or YYYYMMDD to year YYYY, month MM and day DD
% ------------------------------------------------------------------------------------------------------------
function [d,m,y] = partNumDate(n)
% Day, month and year
d      = mod(n,1e2);
m      = fix(mod(n/1e2,1e2));
y      = fix(n/1e4);
% If the number is supplied as YYMMDD (ex: 990123) or CYYMMDD (ex:1010123 --> 2001-01-23) instead of YYYYMMDD (ex: 19990123)
idx    = ~fix(n/1e7);
y(idx) = y(idx) +1900;
end