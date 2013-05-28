function img=rad_mat(scanner,runno,input,options)
% rad_mat
% does part at a time or full data recon proecssing in matlab.
% hope to have this 
% for each chunk 
% load(partial or full)
% regrid(partial or full)
% filter(partial or full)
% fft (partial or full)
% save.
% 
% scanner  - short name of scanner to get data input from
% runno    - run number for output
% input    - string or cell array of the data name on scanner
%          - for agilent 20120101_01/ser01.fid
%          - for bruker   {'patientid','scanid'}  
%                (datanum is optional)
% option   - for options of course.
%


% supporting for sure, bruker or agilent data location convention. 
% have to pass puller simple the correct info to get everything we need. 
% perhaps puller simple will understand bruker format data a bit....
% patientid study scan[:datanum]/rname_01/sname_01

%% data setup
data_buffer=large_array;
data_buffer.addprop('data');
data_buffer.addprop('scanner_constants');
data_buffer.addprop('engine_constants');
data_buffer.addprop('headfile');     % ouput headfile to dump or partial output for multi sets.
data_buffer.addprop('input_headfile'); % scanner input headfile 
data_buffer.headfile=struct;

%% arguments handling
if ~iscell(input)
    input={input};
end

%switch for setting options might be better served ina little struct?
if exist('options','var')
    if ~iscell(options)
        options={options};
    end
else
    options={};
end
% define the possible options, so we can error for unrecognized options.
% 3 classes of options,
% standard, ready for use, 
% beta,     just written tested very little
% planned,  an inkling that they're desried, possibly started etc.
standard_options={ 
    ''
    'overwrite'
    'existing_data'
    'skip_mem_checks'
    'testmode'
    'write_output'     % disable all output saving, good for running inside matlab and continueing in another function
    'skip_write_civm_raw' % do now save civm raw files.
    'skip_write_headfile'
    'write_unscaled'  % save unscaled nifti's in the work directory 
    'display_kspace'
    'display_output'
    ''
    };
beta_options={
    ''
    'planned_ok'    % specaial option which must be early in list of options, controlls whether planned optinos are an error
    'unrecognized_ok'
    'debug_mode'    % way to set our verbosity.
    'channel_alias' %list of values for aliasing channels to letters, could be anything using this
    'combine_method'
    'write_complex'
    'skip_filter'   % does not filter data sets.
    'skip_recon'    % for re-writing headfiles only, implies skip filter.
    'output_order'
    ''
    };
planned_options={
    ''
    'write_phase'
    'fp32_magnitude'
    'write_kimage'
    ''
    };
beta_options_string=strjoin(beta_options(:,1)',' ');
planned_options_string=strjoin(planned_options',' ');
standard_options_string=strjoin(standard_options',' ');
all_options=[standard_options; beta_options; planned_options];
% make all options = false, set some defaults right after this.
for o_num=1:length(all_options)
    if ~exist('opt_struct.(all_options{o})','var') && ~isempty(all_options{o_num})
        opt_struct.(all_options{o_num})=false;
    end
end
%%% set default options
opt_struct.debug_mode=10;
opt_struct.channel_alias=[... % just a lookup of letters to assign to channel data, we'll reserve _m numbers for acquisition params other than channels, eg. time, te, tr alpha, gradients
    'a' 'b' 'c' 'd' 'e' 'f' 'g' 'h' 'i' 'j' 'k' 'l' 'm' ...
    'n' 'o' 'p' 'q' 'r' 's' 't' 'u' 'v' 'w' 'x' 'y' 'z' ];
opt_struct.puller_option_string='';
opt_struct.write_output=true;     % normally we want to save output
opt_struct.combine_channels=true; % normally we want to combine channels
% opt_struct.display_kspace=false;
% opt_struct.display_output=false;
% 
opt_struct.output_order='xyzcpt'; % order of dimensions on output. p is parameters, c is channels. 
opt_struct.combine_method='mean';
% opt_struct.combine_method='square_and_sum';
%%% handle options cellarray.
% look at all before erroring by placing into cellarray err_strings or
% warn_strings.
warn_string='';
err_string='';
for o_num=1:length(options)
    option=options{o_num};
    %%% see what kind of option and add to error and warning message if not
    %%% standard/allowed.
    value=true;
    specific_text='';
    if regexpi(option,'=')
        parts=strsplit(option,'=');
        if length(parts)==2
            value=parts{2};
            option=parts{1};
        else
            err_string=sprintf('%s ''='' sign in option string %s, however does not split cleanly into two parts',err_string,option);
        end
    end
    if regexpi(standard_options_string,[' ' option ' ']) 
        w=false;
        e=false;
    elseif ~isempty(regexpi(beta_options_string,[' ' option ' ']))
        w=true;
        e=false;
        specific_text='is a beta option, CHECK YOUR OUTPUTS CAREFULLY! and use at own risk.';
    elseif regexpi(planned_options_string,[' ' option ' '])
        w=false;
        e=true;
        specific_text='is at best partially implemented.';
        if opt_struct.planned_ok  % allows planned options to pass through.
            w=true;
            e=false;
            specific_text=sprintf( '%s you enabled it with planned_ok',specific_text);
        end
        specific_text=sprintf('%s if you''re sure you want to use it add the planned_ok option also.',specific_text );
    else
        w=false;
        e=true;
        specific_text='not recognized.';
        if opt_struct.unrecognized_ok  % allows unrecognized options to pass through.
            w=true;
            e=false;
            specific_text=sprintf('%s Maybe it is used in some secondary code which did not update the allowed options here.\n continuing.',specific_text);
        end
    end
    if w
        warn_string=sprintf('%s\n ''%s'' option %s',warn_string,option,specific_text);        
    end
    if e
        err_string=sprintf('%s\n ''%s'' option %s',err_string,option,specific_text);
    end
    %%% since we're a struct its easy to add options that dont exist etc,
    %%% we'll just error because they were recongnized as unexpected above.
    opt_struct.(option)=value;
end
if ~isempty(warn_string)
    warning('\n%s\n',warn_string);
    pause(3);
end
if ~isempty(err_string)
    useage_string=help('rad_mat');
    error('\n%s%s\n',useage_string,err_string);
end

if opt_struct.overwrite
    opt_struct.puller_option_string=[' -o ' opt_struct.puller_option_string];
end
if opt_struct.existing_data
    opt_struct.puller_option_string=[' -e ' opt_struct.puller_option_string];
end

data_buffer.scanner_constants=load_scanner_dependency(scanner);
data_buffer.engine_constants=load_engine_dependency();
data_buffer.headfile.matlab_functioncall=['rad_mat('''  scanner ''', ''' runno ''', {''' strjoin(input,''', ''') '''} ' ', {''' strjoin(options,''', ''') '''})'];

clear o_num options option all_options standard_options standard_options_string beta_options beta_options_string planned_options planned_options_string specific_text value err_strings warn_strings e w parts;

%% data pull and build header from input

if strcmp(data_buffer.scanner_constants.scanner_vendor,'agilent')
    dirext='.fid';
else
    dirext='';
end
if numel(input)==1
    input= strsplit(input{1},'/');
    
end
if numel(input)==2 && strcmp(data_buffer.scanner_constants.scanner_vendor,'bruker')
    input{1}=[input{1} '*'];
end %else
puller_data=[ input{1} '/' input{2} dirext];
datapath=[data_buffer.scanner_constants.scanner_data_directory '/' puller_data ];
data_buffer.input_headfile.origin_path=datapath;
% display(['data path should be omega@' scanner ':' datapath ' based on given inputs']);
% display(['base runno is ' runno ' based on given inputs']);

%pull the data to local machine
work_dir_name= [runno '.work'];
work_dir_path=[data_buffer.engine_constants.engine_work_directory '/' work_dir_name];
if ~opt_struct.existing_data
    cmd=['puller_simple ' opt_struct.puller_option_string ' ' scanner ' ''' puller_data ''' ' work_dir_path];
    s =system(cmd);
    if s ~= 0
        error('puller failed:%s',cmd);
    end
end

% load data header given scanner and directory name
data_buffer.input_headfile=load_scanner_header(scanner, work_dir_path );
data_buffer.headfile=combine_struct(data_buffer.headfile,data_buffer.input_headfile);
data_buffer.headfile=combine_struct(data_buffer.headfile,data_buffer.scanner_constants);
data_buffer.headfile=combine_struct(data_buffer.headfile,data_buffer.engine_constants);
clear datapath dirext input puller_data s ;
%% determing input acquisition type 
% some of this might belong in the load data function we're going to need
data_tag=data_buffer.input_headfile.S_scanner_tag;
vol_type=data_buffer.input_headfile.([data_tag 'vol_type']);
% vol_type can be 2D or 3D
scan_type=data_buffer.input_headfile.([data_tag 'vol_type_detail']);
% vol_type_detail says the type of volume we're dealing with, 
% this is set in the header parser perl modules the type can be
% single
% DTI
% MOV
% slab
% multi-vol
% multi-vol-interleave %%%% NOT IMPLMENTED YET IN HEADER PARSER
%                            > THIS WILL BE FOR MULTI-CHANNEL DATA
% multi-echo
% multi-echos are normally interleaved, so we cut our chunk size in necho pieces
% mutli-echo-non_interleave %%%% NOT IMPLEMENTED YET IN HEADER PARSER
%                               > MAY NEVER HAPPEN.

in_bitdepth=data_buffer.input_headfile.([data_tag 'kspace_bit_depth']);
in_bytetype=data_buffer.input_headfile.([data_tag 'kspace_data_type']);

if strcmp(in_bytetype,'Real')
    in_bytetype='float';
elseif strcmp(in_bytetype,'Signed');
    in_bytetype='int';
elseif strcmp(in_bytetype,'UnSigned');
    in_bytetype='uint';
end
% if in_bitdepth==32 || in_bitdepth==64
in_precision=[in_bytetype num2str(in_bitdepth)];
% end
% if regexp(scan_type,'echo')
%     volumes=data_buffer.input_headfile.([data_tag 'echos']);
%     if regexp(scan_type,'non_interleave')
%         interleave=false;
%     else
%         interleave=true;
%     end
% else
%     volumes=data_buffer.input_headfile.([data_tag 'volumes']);
%     if regexp(scan_type,'interleave')
%         interleave=true;
%     else
%         interleave=false;
%     end
% end
volumes=data_buffer.input_headfile.([data_tag 'volumes']);
if regexp(scan_type,'channel')
    warning('multi-channel support still poor.');
end
%% calculate required disk space
bytes_per_pix_output=(2+8+4+4);
% calculate space required on disk to save the output.
% 2 bytes for each voxel in civm image, 8 bytes per voxel of complex output
% if saved, 4 bytes for save 32-bit mag, 4 bytes for save 32-bit phase
voxel_count=volumes*...
    data_buffer.input_headfile.dim_X*...
    data_buffer.input_headfile.dim_Y*...
    data_buffer.input_headfile.dim_Z;
required_free_space=voxel_count*bytes_per_pix_output;

%% disk usage checking
fprintf('Required disk space is %0.2fMB\n',required_free_space/1024/1024);
%%% get free space

[~,local_space_bytes] = unix(['df ',data_buffer.engine_constants.engine_work_directory,' | tail -1 | awk ''{print $4}'' ']);
local_space_bytes=512*str2double(local_space_bytes); %this converts to bytes because default blocksize=512 byte
%  required_free_space=npoints*ntraces*nblocks*10; %estimate we need at least 10 bytes per image point because we save an unscaled 32 bit and a 16 bit and compelx
fprintf('Available disk space is %0.2fMB\n',local_space_bytes/1024/1024)
if required_free_space<local_space_bytes
    fprintf('      .... Proceding with plenty of disk space\n');
else
    error('not enough free local disk space to reconstruct data, delete some files and try again');
end

clear local_space_bytes status required_free_space bytes_per_pix_output;


%% RAM usage checking and load_data parameter determination
display('Determining RAM requirements and chunk size');
data_prefix=data_buffer.input_headfile.(['U_' 'prefix']);
meminfo=imaqmem; %check available memory
copies_in_memory=3; % number of copies of each point required to do work. 
                    %    (as we improve we should update this number)
                    % in theory, 
                        % 1 copy to load, 
                        % 1 copy for filter, 
                        % 1 copy for output files
bytes_per_vox=8;    % number of bytes each voxel requires in memory. 
                    % 4 for single precision, 8 for double, generally
                    % matlab requires single or double, and we cant
                    % calculate in short
                    
binary_header_size   =data_buffer.input_headfile.binary_header_size; %distance to first data point in bytes
load_skip            =data_buffer.input_headfile.block_header_size;  %distance between blocks of rays in file
ray_blocks           =data_buffer.input_headfile.ray_blocks;         %number of blocks of rays total, sometimes nvolumes, sometimes nslices, somtimes nechoes, ntrs nalphas
rays_per_block       =data_buffer.input_headfile.rays_per_block;     %number or rays per in a block of input data, 
ray_length           =data_buffer.input_headfile.ray_length;         %number of samples on a ray, or trajectory (this is doubled due to complex data being taken as real and imaginary discrete samples.)
% ne                   =data_buffer.input_headfile.ne;                 % number of echos.
channels             =data_buffer.input_headfile.([data_tag 'channels']); % number of channels.

ray_padding      =0;
% block_factors=factor(ray_blocks);

%%% calculate padding for bruker
if strcmp(data_buffer.scanner_constants.scanner_vendor,'bruker')
    if strcmp(data_buffer.input_headfile.([data_prefix 'GS_info_dig_filling']),'Yes')  %PVM_EncZfRead=1 for fill, or 0 for no fill, generally we fill( THIS IS NOT WELL TESTED)
        %bruker data is usually padded out to a power of 2 or multiple of 3*2^6
        if mod(channels*ray_length,(2^6*3))>0
            ray_length2 = 2^ceil(log2(channels*ray_length));
            ray_length3 = ceil(((channels*(ray_length)))/(2^6*3))*2^6*3;
            if ray_length3<ray_length2
                ray_length2=ray_length3;
            end
        else
            ray_length2=channels*ray_length;
        end
        ray_padding  =ray_length2-channels*ray_length;
        ray_length   =ray_length2;
        input_points = 2*ray_length*rays_per_block/channels*ray_blocks;    % because ray_length is number of complex points have to doubled this.
        min_load_size= ray_length*rays_per_block/channels*(in_bitdepth/8); % amount of bytes of data to load at a time, 
        
%         if mod(ray_length,(2^6*3))>0
%             ray_length2 = 2^ceil(log2(ray_length));
%             ray_length3 = ceil(ray_length/(2^6*3))*2^6*3;
%             if ray_length3<ray_length2
%                 ray_length2=ray_length3;
%             end
%         else
%             ray_length2=ray_length;
%         end
%         ray_padding  =ray_length2-ray_length; % might want this to be divided by 2 depending on when we correct for this and throw it out.
% %         acquired_ray_length=ray_length2;
%         ray_length   =ray_length2;
%         input_points = ray_length*rays_per_block*ray_blocks; % because ray_length is doubled, this is doubled too.
%         min_load_size=ray_length*rays_per_block*(in_bitdepth/8);             % amount of data to load at a time, (should be single 2dft's worth of data)

    else
        error(['Found no pad option with bruker scan for the first time,' ...
            'Tell james let this continue in test mode']);
    end
else
    input_points         = 2*ray_length*rays_per_block*ray_blocks; % because ray_length is doubled, this is doubled too. 
    min_load_size=ray_length*rays_per_block*(in_bitdepth/8);             % amount of data to load at a time, (should be single 2dft's worth of data)
    % not bruker, no ray padding...
end
total_memory_required= (input_points+voxel_count*copies_in_memory)*bytes_per_vox;
system_reserved_memory=2*1024*1024;% reserve 2gb for the system while we work. 

% handle ignore memory limit options
if opt_struct.skip_mem_checks==1;
    display('you have chosen to ignore this machine''s memory limits, this machine may crash');
    total_memory_required=1;
end

%%% set number of chunks and chunk size based on memory required and
%%% total memory available. if volume will fit in memory happily will
%%% evaluate to num_chunks=1
min_chunks=ceil(total_memory_required/(meminfo.TotalPhys-system_reserved_memory));
memory_space_required=(total_memory_required/min_chunks);
max_loadable_chunk_size=(input_points*(in_bitdepth/8))/min_chunks;

%%% use block_factors to find largest block size to fin in
%%% max_loadable_chunk_size, and set c_dims
c_dims=[ data_buffer.input_headfile.dim_X,...
    data_buffer.input_headfile.dim_Y,...
    data_buffer.input_headfile.dim_Z];
warning('c_dims set poorly just to volume dimensions for now');


%%% first just try a purge to free enough space.
if meminfo.AvailPhys<memory_space_required
    system('purge');
end
%%% now prompt for program close and purge each time
while meminfo.AvailPhys<memory_space_required 
    input('you have too many programs open.\n close some programs and then press enter >> ','s');
    system('purge');
end
%%% Load size calculation, 
max_loads_per_chunk=max_loadable_chunk_size/min_load_size;
if floor(max_loads_per_chunk)<max_loads_per_chunk
    error('un-even loads per chunk size, have to do better job getting loading sizes');
end
chunk_size=floor(max_loadable_chunk_size/min_load_size)*min_load_size;
% kspace_file_size=binary_header_size+(load_size+load_skip)*ray_blocks*volumes; % total ammount of data in data file.

kspace_header_bytes  =binary_header_size+load_skip*(ray_blocks-1); 
    % total bytes used in header into throught out the kspace data
kspace_data          =input_points*(in_bitdepth/8);
    % total bytes used in data only(no header/meta info)
kspace_file_size     =kspace_header_bytes+kspace_data; % total ammount of data in data file.
num_chunks           =kspace_data/chunk_size;
if floor(num_chunks)<num_chunks
    warning('Number of chunks did not work out to integer, things may be wrong!');
end
if min_load_size>chunk_size && skip_mem_checks==false
    error('Oh noes! blocks of data too big to be handled in a single chunk, bailing out');
end
fileInfo = dir(data_buffer.input_headfile.kspace_data_path);
measured_filesize    =fileInfo.bytes;

if kspace_file_size~=measured_filesize
    error('Measured data file size and calculated dont match. WE''RE DOING SOMETHING WRONG!\nMeasured=%d\nCalculated=%d\n',measured_filesize,kspace_file_size);
end
min_load_size=min_load_size/(in_bitdepth/8);
chunk_size=chunk_size/(in_bitdepth/8);
if num_chunks>1
    error('not tested with more than one chunk yet');
end

% need to get n samples from data set here. We're going to just assume
% cartesian samples all time for now.
% voldims=[procpar.np/2 procpar.nv procpar.nv2];
% nvols=(npoints/2*ntraces*nblocks)/prod(voldims);
% blocks_per_vol=nblocks/nvols;
% % fov=[procpar.lro procpar.lpe procpar.lpe2].*10; %fov in mm this may not be right for multislice data
% % res=fov./voldims;

% %check to see if we need to do this in chunks or not
% if volumes>1 %recon one volume at a time
%     num_chunks=volumes;
%     max_blocks=blocks_per_vol;
%     if max_blocks*npoints*ntraces>memory_space_required
%         error('volume size is too large, consider closing programs and restarting')
%     end
% else %if its just one volume, see if we can do it all at once or need to do chunks
%     max_blocks=floor(memory_space_required/(ntraces*npoints)); %number of blocks we can work on at a time
%     num_chunks=ceil(nblocks/max_blocks);
% end
fprintf('    ... Proceding doing recon with %d chunk(s)\n',num_chunks);

clear ray_length2 ray_length3 fileInfo bytes_per_vox copies_in_memory in_bitdepth in_bytetype min_chunks system_reserved_memory total_memory_required memory_space_required meminfo measured_filesize kspace_file_size kspace_data kspace_header_bytes ;


%% collect gui info (or set testmode)
%check civm runno convention
if ~regexp(runno,'^[A-Z][0-9]{5-6}.*')
    %~strcmp(runno(1),'S') && ~strcmp(runno(1),'N') || length(runno(2:end))~=5 || isnan(str2double(runno(2:end)))
    display('runno does not match CIVM convention, the recon will procede in testmode')
    opt_struct.testmode=1;
end
% if not testmode then create headfile
if  opt_struct.testmode==1
    display('this recon will not be archiveable');
%     data_buffer.headfile=0;
else
    display('gathering gui info');
    display(' ');
%     if opt_struct.fp32_magnitude==1 || opt_struct.write_phase==1
%         img_format='fp32';
%     else
%         img_format='raw';
%     end
%     headfile=create_agilent_headfile(procpar,img_format,runno);
    data_buffer.engine_constants.engine_recongui_menu_path;
    [~, gui_dump]=system(['$GUI_APP ' ...
        ' ''' data_buffer.engine_constants.engine_constants_path ...
        ' ' data_buffer.engine_constants.engine_recongui_menu_path ...
        ' ' data_buffer.scanner_constants.scanner_tesla ...
        ' ''']);
    gui_info_lines=strtrim(strsplit(gui_dump,'\n'));
    for l=1:length(gui_info_lines) 
        guiinfo=strsplit(gui_info_lines{l},':::');
        if length(guiinfo)==2
            data_buffer.headfile.(['U_' guiinfo{1}])=guiinfo{2};
            fprintf('adding meta line %s=%s\n', ['U_' guiinfo{1}],data_buffer.headfile.(['U_' guiinfo{1}]));
        else 
            fprintf('ignoring line %s\n',gui_info_lines{l});
        end
    end
    clear gui_info gui_dump gui_info_lines l;
end

%%% this data get for dimensions is temporary, should be handled better in
%%% the future.
x=data_buffer.input_headfile.dim_X;
y=data_buffer.input_headfile.dim_Y;
z=data_buffer.input_headfile.dim_Z;
channels=data_buffer.input_headfile.([data_tag 'channels'] );
if isfield (data_buffer.input_headfile,[data_tag 'varying_parameter'])
    varying_parameter=data_buffer.input_headfile.([data_tag 'varying_parameter']);
else
    varying_parameter='';
end
if strcmp(varying_parameter,'echos')
    params=data_buffer.input_headfile.ne;
elseif strcmp(varying_parameter,'alpha')
    params=length(data_buffer.input_headfile.alpha_sequence);
elseif strcmp(varying_parameter,'tr')
    params=length(data_buffer.input_headfile.tr_sequence);
elseif regexpi(varying_parameter,',')
    error('MULTI VARYING PARAMETER ATTEMPTED:%s THIS HAS NOT BEEN DONE BEFORE.',varying_parameter);
else
    fprintf('No varying parameter\n');
    params=1;
end
timepoints=data_buffer.input_headfile.([data_tag 'volumes'])/channels/params;
input_dimensions=[ x channels params z y timepoints] ;
output_dimensions=[ x y z  channels params timepoints ];
%% do work.
% for each chunk, load chunk, regrid, filter, fft, (save) 
% save not implemented yet, requires a chunk stitch funtion as well. 
% for now assuming we didnt chunk and saves after the fact.
% 
for chunk_num=1:num_chunks
    if ~opt_struct.skip_recon
    %%% LOAD
    chunks_to_load=[1];
    %load data with skips function, does not reshape, leave that to regridd
    %program.
    
    load_from_data_file(data_buffer, data_buffer.input_headfile.kspace_data_path, ....
        binary_header_size, min_load_size, load_skip, in_precision, chunk_size, ...
        num_chunks,chunks_to_load(chunk_num))
    
    if ray_padding>0  %remove extra elements in padded ray,
        % lenght of full ray is spatial_dim1*nchannels+pad
        %         reps=ray_length;
        % account for number of channels and echos here as well .
        logm=zeros((ray_length-ray_padding)/4,1);
        logm(ray_length-ray_padding+1:ray_length)=1;
        logm=logical(repmat( logm, length(data_buffer.data)/(ray_length),1) );
        data_buffer.data(logm)=[];
        warning('padding correction applied, hopefully correctly.');
        % could put sanity check that we are now the number of data points
        % expected given datasamples, so that would be
        % (ray_legth-ray_padding)*rays_per_blocks*blocks_per_chunk
        % NOTE: blocks_per_chunk is same as blocks_per_volume with small data,
        if numel(data_buffer.data) ~= (ray_length-ray_padding)/channels*rays_per_block
            error('Ray_padding reversal went awrry. Data length should be %d, but is %d',(ray_length-ray_padding)/channels*rays_per_block,numel(data_buffer.data));
        else
            fprintf('Data padding retains corrent number of elements, continuing...\n');
        end
    end
    %%% pre regrid data save.
    %     if opt_struct.display_kspace==true
    %         input_kspace=reshape(data_buffer.data,input_dimensions);
    %     end
    %%% REGRID  just simple reshape for cartesian
    rad_regid(data_buffer,c_dims);
    if opt_struct.display_kspace==true
        %         kslice=zeros(size(data_buffer.data,1),size(data_buffer.data,2)*2);
        kslice=zeros(size(data_buffer.data,1),size(data_buffer.data,2));
        for tn=1:timepoints
            for zn=1:z
                for pn=1:params
                    for cn=1:channels
                        fprintf('p:%dc:%d ',pn,cn);
                        kslice(1:size(data_buffer.data,1),1:size(data_buffer.data,2))=data_buffer.data(:,:,zn,cn,pn,tn);
                        %                         kslice(1:size(data_buffer.data,1),size(data_buffer.data,2)+1:size(data_buffer.data,2)*2)=input_kspace(:,cn,pn,zn,:,tn);
                        imagesc(log(abs(squeeze(kslice))));
                        %                             fprintf('.');
                        pause(4/z/channels/params);
                        %                         pause(1);
                        %                         imagesc(log(abs(squeeze(input_kspace(:,cn,pn,zn,:,tn)))));
                        %                             fprintf('.');
                        %                         pause(4/z/channels/params);
                        %                         pause(1);
                    end
                    fprintf('\n');
                end
            end
        end
    end
    if ~opt_struct.skip_filter
        if strcmp(vol_type,'2D')
            data_buffer.data=reshape(data_buffer.data,[ output_dimensions(1:2) prod(output_dimensions(3:end))] );
            data_buffer.data=fermi_filter_isodim2(data_buffer.data,'','',true);
            data_buffer.data=reshape(data_buffer.data,output_dimensions );
        end
        % rad_filter(data_buffer,c_dims);
    end
    %% fft
    if strcmp(vol_type,'2D')
        if ~exist('img','var')
            img=zeros(output_dimensions);
        end
        %         xyzcpt
        for cn=1:channels
            if opt_struct.debug_mode>=10
                fprintf('channel %d working...\n',cn);
            end
            for tn=1:timepoints
                for pn=1:params
                    if opt_struct.debug_mode>=20
                        fprintf('p%d ',pn);
                    end
                    %   data_buffer.data(:,:,:,cn,pn,tn)=fermi_filter_isodim2(data_buffer.data(:,:,:,cn,pn,tn),'','',true);
                    img(:,:,:,cn,pn,tn)=fftshift(ifft2(fftshift(data_buffer.data(:,:,:,cn,pn,tn))));
                    if opt_struct.debug_mode>=20
                        fprintf('\n');
                    end
                end
            end
        end
    else
        img=fftshift(ifftn(data_buffer.data));
    end
    
    if opt_struct.display_output==true
        for zn=1:z
            for tn=1:timepoints
                for pn=1:params
                    for cn=1:channels
                        imagesc(log(abs(squeeze(img(:,:,zn,cn,pn,tn)))));
                        pause(30/z/channels/params);
                        
                    end
                end
                fprintf('%d %d\n',zn,tn);
            end
        end
    end
    if opt_struct.combine_channels && channels>1
        % image order is expected to be xyzcpt
        fprintf('combining channel complex data with method %s\n',opt_struct.combine_method);
        if regexpi(opt_struct.combine_method,'mean')
            combine_image=squeeze(mean(img,4));
        end
        if regexpi(opt_struct.combine_method,'square_and_sum')
            combine_image=squeeze(mean(img.^2,4));
        end
    end
    %     error('Code very unfinished, just meta data and setup done now.');
    % foreach interleave ( separate out interleaved acquistions to recon one at a time)
    %     for interleave_num=1:n_interleaves
    %         % we're cartesean for now  so no regrid
    %         % regrid(data_buffer.data,regrid_method);
    %         filter(data_buffer,interleave_num);
    %         fft(data_buffer,interleave_num);
    %         savedata(data_buffer,interleave_num,outloc);
    %     end
    else
        img='RECON_DISABLED';
    end
end % end foreachchunk

warning('this saving code is temporary it is not designed for chunnks');
%% save data
% this needs a bunch of work, for now it is just assuming the whole pile of
% data is sitting in memory awaiting saving, does not handle chunks or
% anything correctly just now. 

%  mag=abs(raw_data(i).data);

if opt_struct.write_output
    work_dir_img_path_base=[ work_dir_path '/' runno ] ;
    %%% save n-D combined nii.
    if opt_struct.combine_channels && channels>1 && ~opt_struct.skip_recon
        if ~exist([work_dir_img_path_base '.nii'],'file') || opt_struct.overwrite
            fprintf('Saving combine channel image to output work dir, using method: %s\n',opt_struct.combine_method);
            nii=make_nii(abs(combine_image), [ ...
                data_buffer.headfile.fovx/data_buffer.headfile.dim_X ...
                data_buffer.headfile.fovy/data_buffer.headfile.dim_Y ...
                data_buffer.headfile.fovz/data_buffer.headfile.dim_Z]); % insert fov settings here ffs....
            save_nii(nii,[work_dir_img_path_base '.nii']);
        else
            warning('Combined Image already exists and overwrite disabled');
        end
    end
    
    max_mnumber=timepoints*params;
    m_length=length(num2str(max_mnumber));
    if opt_struct.combine_channels
        channels=1;
    end
    for tn=1:timepoints
        for cn=1:channels
            for pn=1:params
                if ~opt_struct.skip_recon
                    if opt_struct.combine_channels
                        tmp=squeeze(combine_image(:,:,:,pn,tn));
                    else
                        tmp=squeeze(img(:,:,:,cn,pn,tn));% pulls out one volume at a time.
                    end
                else
                    tmp=img;
                end
                fprintf('Extracting image channel:%0.0f param:%0.0f timepoint:%0.0f\n',cn,pn,tn);
                %%%set channel and mnumber codes for the filename
                if channels>1
                    channel_code=opt_struct.channel_alias(cn);
                else
                    channel_code='';
                end
                m_number=(tn-1)*params+pn;
                if timepoints> 1 || params >1
                    m_code=sprintf(['_m%0' num2str(m_length) '.0f'], m_number);
                else
                    m_code='';
                end
                
                work_dir_img_path=[work_dir_img_path_base channel_code m_code];
                %%% complex save
                if opt_struct.write_complex && ~opt_struct.skip_recon
                    fprintf('\tradish_complex save\n');
                    save_complex(tmp,[ work_dir_img_path '.out']);
                end
                if opt_struct.write_kimage && ~opt_struct.skip_recon
                    fprintf('\tradish_complex kimage save\n');
                    % save data_buffer.data to work dir
                end
                %%% nii_save
                if opt_struct.write_unscaled && ~opt_struct.skip_recon
                    fprintf('\tunscaled_nii save\n');
                    nii=make_nii(abs(tmp), [ data_buffer.headfile.fovx/data_buffer.headfile.dim_X data_buffer.headfile.fovy/data_buffer.headfile.dim_Y data_buffer.headfile.fovz/data_buffer.headfile.dim_Z]); % insert fov settings here ffs....
                    save_nii(nii,[work_dir_img_path '.nii']);
                end
                %%% civmraw save
                space_dir_img_name =[ runno channel_code m_code];
                space_dir_img_folder=[data_buffer.engine_constants.engine_work_directory '/' space_dir_img_name '/' space_dir_img_name 'images' ];
                if ~exist(space_dir_img_folder,'dir')
                    mkdir(space_dir_img_folder);
                elseif ~opt_struct.overwrite
                    % the folder existed, however we were not set for
                    % overwrite
                    error('Output directory existed! NOT OVERWRITING SOMEONE ELSES DATA UNLESS YOU TELL ME!, use overwrite option.');
                end
                %%% set param value in output
                % if te
                % if alpha
                data_buffer.headfile.te=data_buffer.headfile.te_sequence(pn);
                if ~opt_struct.skip_write_headfile
                    fprintf('\tHeadfile save\n');
                    write_headfile([space_dir_img_folder '/' space_dir_img_name '.headfile'],data_buffer.headfile);
                end
                if (opt_struct.fp32_magnitude==true)
                    datatype='fp32';
                else
                    datatype='raw';
                end
                if ~opt_struct.skip_write_civm_raw && ~opt_struct.skip_recon
                    fprintf('\tcivm_raw save\n');
                    complex_to_civmraw(tmp,[ runno channel_code],data_buffer.scanner_constants.scanner_tesla_image_code,space_dir_img_folder,'auto','',1,datatype)
                end
                
            end
        end
    end
end


end
