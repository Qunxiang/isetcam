function sensor = sensorSet(sensor,param,val,varargin)
%Set ISETCam sensor parameters.
%
%   sensor = sensorSet(sensor,param,val,varargin);
%
% This routine sets the ISETCam sensor parameters.  See sensorGet for the
% longer list of derived parameters.
%
% In addition to setting sensor parameters, it is possible to use this
% routine to set pixel parameters using the syntax:
%
%     sensorSet(sensor,'pixel param',val);
%
% As of April 2014, we are using this approach more than the previous
% approach
%    pixel = sensorGet(sensor,'pixel');
%    pixel = pixelSet(pixel,'param',val);
%    sensor = sensorSet(sensor,'pixel',pixel);
%
% Examples:
%    sensor = sensorCreate; pixel = pixelCreate;
%    sensor = sensorSet(sensor,'pixel',pixel);
%    sensor = sensorSet(sensor,'auto exposure',1);   ('on' and 'off' work, too)
%    sensor = sensorSet(sensor,'sensor compute method',baseName);
%    sensor = sensorSet(sensor,'quantization method','10 bit');
%    sensor = sensorSet(sensor,'analog gain',5);
%    sensor = sensorSet(sensor,'pixel size same fill factor',1.2e-6);
%    sensor = sensorSet(sensor,'pixel voltage swing',1.2);
%    sensor = sensorSet(sensor,'response type','log'); % 'linear' or 'log'
%
% General
%      {'name'} - This sensor's identifier
%      {'rows'} - number of rows
%      {'cols'} - number of cols
%      {'size'} - [rows,cols]
%      {'fov'}  - horizontal field of view.  NOTE: Also adjusts row/col!
%
% Color
%      {'color'}  - structure containing color information
%        {'filter transmissivities'}   - color filter transmissivities
%            (also, 'filter spectra')
%        {'filter names'}   - color filter names
%        {'infrared filter'}  - IR filter transmissivity
%      {'spectrum'}           - wavelength spectrum structure
%        {'wavelength'}       - wavelength samples
%      {'color filter array'} - color filter array structure
%        {'cfa pattern'}          - color filter array (cfa) pattern
%        {'cfa pattern and size'} - set cfa pattern and adjust sensor size if 
%                                   there is a new block size
%
% Electrical and imaging
%      {'data'}               - data structure
%        {'volts'}            - voltage responses
%        {'digitalValues'}    - digital values
%      {'analog gain'}        - Transform volts
%      {'analog offset'}      - Transform volts
%            Formula for offset and gain: (v + analogOffset)/analogGain)
%
%      {'roi'}                - region of interest information 
%                               (roiLocs, Nx2, or rect 1x4 format)
%      {'cds'}                - correlated double sampling flat
%      {'quantization method'}- method used for quantization 
%                               ('analog', '10 bit', '8 bit', '12 bit')
%      {'response type'}  - We allow a 'log' sensor type.  Default is
%                          'linear'.  For the 'log' type, we convert
%                          the pixel voltage by log10() on return.
%
%      {'dsnu image'}         - Dark signal non uniformity (DSNU) image
%      {'prnu image'}         - Photo response non uniformity (PRNU) image
%      {'dsnu level'}         - dark signal nonuniformity (std dev)
%      {'prnu level'}         - photoresponse nonuniformity (std dev)
%      {'column fpn parameters'} - column fpn parameters, both offset and gain
%      {'col gain fpn vector'}   - column gain fpn data
%      {'col offset fpn vector'} - column offset fpn data
%      {'noise Flag'}         - 0 means no noise
%                               1 means only shot noise,
%                               2 means shot noise and electronics noise
%      {'reuse noise'}        - Generate noise from current seed
%      {'noise seed'}         - Saved noise seed for randn()
%
%      {'exposure time'}       - exposure time in seconds
%      {'exposure plane'}      - selects exposure for display
%      {'auto exposure'}       - auto-exposure flag, 1 or 0
%                                'on' and 'off' are also OK.
%
% Pixel
%      {'pixel'}
%
% Optics
%      {'vignetting'}
%      {'microlens'}
%      {'sensor etendue'}
%      {'microlens offset'}  - used with microlens window toolbox
%
% Computational method
%      {'sensor compute method'}- special algorithm, say for sensor binning
%      {'ngridsamples'}       - number of spatial grid samples within a pixel
%
% Check for consistency between GUI and data
%      {'consistency'}
%
% Miscellaneous
%     {'mcc rect handles'}  - Handles for the rectangle selections in an MCC
%     {'mcc corner points'} - Corner points for the whole MCC chart
%     {'gamma'}           - Display gamma for the window
%
% Sensor motion
%     {'sensor movement'}  - A structure with sensor motion information 
%     {'movement positions'} - Nx2 vector of (x,y) positions in deg
%     {'framesPerPosition'}- Exposure times per (x,y) position
%  
% Private
%      {'editfilternames'}
%
% Copyright ImagEval Consultants, LLC, 2003.


%% Check parameters and special cases

if ~exist('param','var') || isempty(param), error('Parameter field required.'); end

% Empty is an allowed value.  So we don't use ieNotDefined.
if ~exist('val','var'),   error('Value field required.'); end

[oType, param] = ieParameterOtype(param);

%% Handle the case of a pixelSet via this sensorSet call.
if isequal(oType,'pixel')
    if isempty(param)
        % oi = oiSet(oi,'optics',optics);
        sensor.pixel = val;
        return;
    else
        if isempty(varargin), sensor.pixel = pixelSet(sensor.pixel,param,val);
        elseif length(varargin) == 1
            sensor.pixel = pixelSet(sensor.pixel,param,val,varargin{1});
        elseif length(varargin) == 2
            sensor.pixel = pixelSet(sensor.pixel,param,val,varargin{1},varargin{2});
        end
        return;
    end
elseif isempty(param)
    error('oType %s. Empty param.\n',oType);
end

%% The usual method of setting sensor parameters starts here

param = ieParamFormat(param);  % Lower case and remove spaces
switch lower(param)

    case {'name','title'}
        sensor.name = val;

    case {'rows','row'}
        % sensor = sensorSet(sensor,'rows',r);
        ubRows = sensorGet(sensor,'unit block rows');
        if ubRows > 0, sensor.rows = round(val/ubRows)*ubRows;
        else,          sensor.rows = val;
        end
        
        % We clear the data at this point to prevent any possibility of a
        % mis-match with the block array size
        sensor = sensorClearData(sensor);
    case {'cols','col'}
        % sensor = sensorSet(sensor,'cols',c);

        % Set sensor cols, but make sure that we align with the proper
        % block size.
        ubCols = sensorGet(sensor,'unit block cols');
        if ubCols > 0, sensor.cols = round(val/ubCols)*ubCols;
        else,         sensor.cols = val;
        end
        % We clear the data at this point to prevent any possibility of a
        % mis-match with the block array size
        sensor = sensorClearData(sensor);
    case {'size'}
        % sensor = sensorSet(sensor,'size',[r c]);
        %
        % There are constraints on the possible sizes because of the block
        % pattern size.  This handles that issue.  Consequently, the actual
        % size may differ from the set size.
        %
        % There are cases when we want to set a FOV rather than size.  See
        % sensorSetSizeToFOV for those cases.

        % Not sure why the size checking is needed for human case.  Check.
        % It's a problem in sensorCompute.
        sensor = sensorSet(sensor,'rows',val(1));
        sensor = sensorSet(sensor,'cols',val(2));
        sensor = sensorClearData(sensor);

        % In the case of human, resetting the size requires rebuilding the
        % cone mosaic - Could be removed and use only ISETBio
        if strfind(sensorGet(sensor,'name'),'human')
            % disp('Resizing human sensor')
            if checkfields(sensor,'human','coneType')
                d = sensor.human.densities;
                rSeed = sensor.human.rSeed;
                umConeWidth = pixelGet(sensorGet(sensor,'pixel'),'width','um');
                [xy,coneType] = humanConeMosaic(val,d,umConeWidth,rSeed);
                sensor.human.coneType = coneType;
                sensor.human.xy = xy;
                % Make sure the pattern field matches coneType.  It is
                % unfortunate that we have both, though, isn't it?  Maybe
                % we should only have pattern, not coneType?
                sensor = sensorSet(sensor,'pattern',coneType);
            end
        end

    case {'fov','horizontalfieldofview'}
        % sensor = sensorSet(sensor,'fov',newFOV,scene,oi);
        % This set is dangerous because it changes the size.  And size
        % changes the FOV.  So, I am not happy.  But we use it so much that
        % I stuck it in secretly.  But the preferred usage should be:
        % [sensor,actualFOV] = sensorSetSizeToFOV(sensor,newFOV,scene,oi);
        scene = []; oi = [];
        if ~isempty(varargin), scene = varargin{1}; end
        if length(varargin) > 1, oi = varargin{2}; end
        sensor = sensorSetSizeToFOV(sensor,val, scene, oi);
    case 'color'
        sensor.color = val;
    case {'filterspectra','colorfilters','filtertransmissivities'}
        % sensorSet(sensor,'filter spectra',val) The error conditions tests
        % whether we have set 'wave' before we set the color filters.
        if size(val,1) ~= sensorGet(sensor,'n wave')
            error('Color filter size (%i) does not match wave size (%i)',...
                size(val,1),sensorGet(sensor,'n wave'));
        else
            sensor.color.filterSpectra = val;
        end
    case {'colorfilterletters','filternames','filtername'}
        if ~iscell(val), error('Filter names must be a cell array');
        else, sensor.color.filterNames = val;
        end
    case {'editfilternames','editfiltername'}
        % sensor = sensorSet(sensor,'editFilterNames',filterIndex,newFilterName);
        % This call either edits the name of an existing filter (if
        % whichFilter < length(filterNames), or adds a new filter
        %
        sensor = sensorSet(sensor,'filterNames',ieSetFilterName(val,varargin{1},sensor));
    case {'infrared','irfilter','infraredfilter'}
        % This can be a column matrix of filters for different field
        % heights
        % sensorSet(sensor,'irFilter',irFilterMatrix);
        nWave = sensorGet(sensor,'nWave');
        if length(val(:)) == nWave, val = val(:); end
        sensor.color.irFilter = val;

    case {'spectrum'}
        sensor.spectrum = val;
    case {'wavelength','wave','wavelengthsamples'}
        % sensorSet(sensor,'wave',wave) 
        % The pixel structure wave is, unfortunately, a mirror of the
        % sensor wave. So we have to change them both.  We also have to
        % interpolate the other wavelength-dependent filter functions
        % including the irfilter,  the color filters, and the photodetector
        % spectral qe.
        
        oldWave = sensorGet(sensor,'wave');
        newWave = val(:);
        sensor.spectrum.wave = val(:);
        pixel  = sensorGet(sensor,'pixel');        % Adjust pixel wave
        pixel  = pixelSet(pixel,'wave',val(:));
        
        % Interpolate  other wavelength dependent filters 
        if checkfields(sensor,'color')
            cFilters = sensorGet(sensor,'filter spectra');  % Color filters
            cFilters = interp1(oldWave,cFilters,newWave,'linear',0);
            sensor = sensorSet(sensor,'filter spectra',cFilters);
        end
        
        if checkfields(sensor,'color')    
            cFilters = sensorGet(sensor,'ir filter');  % IR filter
            cFilters = interp1(oldWave,cFilters,newWave,'linear',0);
            sensor   = sensorSet(sensor,'ir filter',cFilters);
        end
        
        % Pixel spectral qe is the photodetector spectral qe.
        cFilters = pixelGet(pixel,'spectral qe');
        cFilters = interp1(oldWave,cFilters,newWave,'linear',0);
        pixel    = pixelSet(pixel,'spectral qe',cFilters);
        sensor   = sensorSet(sensor,'pixel',pixel);
        
    case {'integrationtime','exptime','exposuretime','expduration','exposureduration'}
        % Seconds
        sensor.integrationTime = val;
        sensor.AE = 0;
    case {'exposureplane'}
        % Which of the multiple exposures, in a bracketed condition, we
        % show in the window.
        sensor.exposurePlane = round(val);
    case {'autoexp','autoexposure','automaticexposure'}
        % sensorSet(sensor,'auto exposure',1);
        % Boolean flag for turning on auto-exposure.
        if ischar(val)
            % Let the person put on and off into the autoexposure field
            if strcmp(val,'on'), val = 1;
            else,val = 0;
            end
        end
        sensor.AE = val;
        if val
            % If we turn autoexposure 'on' and the exposure mode is CFA, we
            % will set integration time to an array of 0s
            integrationTime = sensorGet(sensor,'Integration Time');
            pattern = sensorGet(sensor,'pattern');
            if isequal( size(integrationTime),size(pattern) )
                sensor.integrationTime = zeros(size(pattern));
            else
                sensor.integrationTime = 0;
            end
        end

    case {'cds','correlateddoublesampling'}
        sensor.CDS = val;
    case {'vignetting','sensorvignetting','bareetendue','sensorbareetendue','nomicrolensetendue'}
        % This is an array that describes the loss of light at each
        % pixel due to vignetting.  The loss of light when the microlens is
        % in place is stored in the sensor.etendue entry.  The improvement of
        % the light due to the microlens is calculated from sensor.etendue ./
        % sensor.data.vignetting.
        sensor.data.vignetting = val;

    case {'data'}
        sensor.data = val;
    case {'voltage','volts'}
        sensor.data.volts = val;
        %  We adjust the row and column size to match the data. The data
        %  size is the factor that determines the sensor row and column values.
        %  The row and col values are only included for those cases when
        %  there are no data computed yet.
    case {'analoggain','ag'}
        sensor.analogGain = val;
    case {'analogoffset','ao'}
        sensor.analogOffset = val;
    case {'dv','digitalvalue','digitalvalues'}
        sensor.data.dv = val;
    case {'roi'}
        sensor.roi = val;
    case {'quantization','qmethod','quantizationmethod'}
        % 'analog', '10 bit', '8 bit', '12 bit'
        sensor = sensorSetQuantization(sensor,val);
    case {'responsetype'}
        % Values can be 'log' or 'linear'
        if ismember(val,{'linear','log'})
            sensor.responseType = val;
        else
            error('Response type must be linear or log');
        end
        
    case {'offsetfpnimage','dsnuimage'} % Dark signal non uniformity (DSNU) image
        sensor.offsetFPNimage = val;
    case {'gainfpnimage','prnuimage'}   % Photo response non uniformity (PRNU) image
        sensor.gainFPNimage = val;
    case {'dsnulevel','sigmaoffsetfpn','offsetfpn','offset','offsetsd','offsetnoisevalue'}
        % Units are volts
        sensor.sigmaOffsetFPN = val;
        % Clear the dsnu image when the dsnu level is reset
        sensor = sensorSet(sensor,'dsnuimage',[]);
    case {'prnulevel','sigmagainfpn','gainfpn','gain','gainsd','gainnoisevalue'}
        % This is stored as a percentage. Always.  This is a change from
        % the past where I tried to be clever but got into trouble.
        sensor.sigmaGainFPN = val;
        % Clear the prnu image when the prnu level is reset
        sensor = sensorSet(sensor,'prnuimage',[]);
    case {'columnfpnparameters','columnfpn','columnfixedpatternnoise','colfpn'}
        if length(val) == 2 || isempty(val), sensor.columnFPN = val;
        else, error('Column fpn must be in [offset,gain] format.');
        end
    case {'colgainfpnvector','columnprnu'}
        if isempty(val), sensor.colGain = val;
        elseif length(val) == sensorGet(sensor,'cols'), sensor.colGain = val;
        else, error('Bad column gain data');
        end
    case {'coloffsetfpnvector','columndsnu'}
        if isempty(val), sensor.colOffset = val;
        elseif length(val) == sensorGet(sensor,'cols'), sensor.colOffset = val;
        else, error('Bad column offset data');
        end
        
        % Noise management
    case {'noiseflag'}
        % NOISE FLAG
        %  The noise flag is an important way to control the details of the
        %  calculation.  The default value of the noiseFlag is 2.  In this case,
        %  which is standard operating, photon noise, read/reset, FPN, analog
        %  gain/offset, clipping, quantization, are all included.  Different
        %  selections are made by different values of the noiseFlag.
        %
        %   sensor = sensorSet(sensor,'noise flag',noiseFlag);
        %
        % The conditions are:
        %
        %  noiseFlag | photon other-noises analog-gain/offset clipping quantization
        %    -1      |   0         0            0                0        0
        %     0      |   0         0            +                +        +
        %     1      |   +         0            +                +        +
        %     2      |   +         +            +                +        +
        sensor.noiseFlag = val;
    case {'reusenoise'}
        % Decide whether we reuse (1) or recalculate (0) the noise.  If we
        % reuse, then we set the randn() stream as per the state below.
        sensor.reuseNoise = val;
    case {'noiseseed'}
        % Used for randn seed.  Some day we will need to update
        % for Matlab's randStream objects.
        sensor.noiseSeed = val;
        
    case {'ngridsamples','pixelsamples','nsamplesperpixel','npixelsamplesforcomputing'}
        sensor.samplesPerPixel = val;
    case {'colorfilterarray','cfa'}
        sensor.cfa = val;
    case {'cfapattern','pattern','filterorder'}
        % sensor = sensorSet(sensor,'cfa pattern',p
        sensor.cfa.pattern = val;
        % Check whether the new pattern size is correctly matched
        % to the sensor size - if not, warn the user.  Use the call below
        % (pattern and size) to force an adjustment
        
        % User should adjust the size to be an integer multiple of the CFA
        % row and col sizes.
        sz = sensorGet(sensor,'size');
        if ~isempty(sz)
            % Should we adjust the sensor here?
            r = size(val,1); c = size(val,2);
            if sz(1) ~= r*round(sz(1)/r), warning('CFA row/pattern mis-match');end
            if sz(2) ~= c*round(sz(2)/c), warning('CFA col/pattern mis-match'); end
        end
    case {'cfapatternandsize','patternsize','patternandsize'}
        % sensorSet(sensor,'pattrn and size',pattern)
        %
        % Often, when we set the pattern we then follow by adjusting the
        % sensor size so that we complete blockss.
        
        % Set the pattern and then adjust the size up
        sensor.cfa.pattern = val;
        
        sz = sensorGet(sensor,'size');
        r = size(val,1); c = size(val,2);
        if sz(1) ~= r*round(sz(1)/r)
            sensor = sensorSet(sensor,'row',r*ceil(sz(1)/r));
        end
        if sz(2) ~= c*round(sz(2)/c)
            sensor = sensorSet(sensor,'col',c*ceil(sz(2)/c));
        end

    case {'pixel','imagesensorarraypixel'}
        sensor.pixel = val;
    case {'pixelsize'}
        % sensorSet(sensor,'pixel size',2-vectorInmeters); 
        % Adjust the pixel size while maintaining the photodetector fill
        % factor The size is specified in meters. It is supposed to be a
        % 2-vector, but if a single number is sent in we convert it to a
        % 2-vector.
        if length(val) == 1, val = [val,val]; end
        pixel  = sensorGet(sensor,'pixel');
        pixel  = pixelSet(pixel,'size',val);
        ff     = pixelGet(pixel,'fill factor');
        sensor = sensorSet(sensor,'pixel',pixel);
        sensor = pixelCenterFillPD(sensor, ff);

        % Microlens related
    case {'microlens','ml'}
        sensor.ml = val;
    case {'etendue','sensoretendue','imagesensorarrayetendue'}
        % The size of etendue should match the size of the sensor array. It
        % is computed using the chief ray angle.
        sensor.etendue = val;
    case {'microlensoffset','mloffset','microlensoffsetmicrons'}
        % This is the offset of the microlens in microns as a function of
        % number of pixels from the center pixel.  The unit is microns
        % because the pixels are usually in microns.  This may have to
        % change to meters at some point for consistency.
        sensor.mlOffset = val;

    case {'consistency','sensorconsistency'}
        sensor.consistency = val;
    case {'sensorcompute','sensorcomputemethod'}
        sensor.sensorComputeMethod = val;

        % These ROIs for the MCC chart should be generalized to chartP here
        % and in ip and other objects.  Maybe there should be a chart
        % struct that is defined.
    case {'mccrecthandles'}
        % These are handles to the squares on the MCC selection regions
        % see macbethSelect.  If we over-write them, we first delete the
        % existing ones.
        if checkfields(sensor,'mccRectHandles')
            if ~isempty(sensor.mccRectHandles)
                try delete(sensor.mccRectHandles(:));
                catch
                end
            end
        end
        sensor.mccRectHandles = val;
    case {'cornerpoints','mccpointlocs','mcccornerpoints'}
        % Corner points for the whole MCC chart
        sensor.mccCornerPoints = val;
        
    case {'gamma'}
        % Adjust the gamma on the display window.
        hdl = ieSessionGet('sensor window handle');
        if ~isempty(hdl)
            set(hdl.editGam,'string',num2str(val));
            % sceneWindow('sceneRefresh',hObj,eventdata,hdl);
            sensorImageWindow;
        end
        
        % Human cone structure - Should be removed and used only in ISETBio
    case {'human'}
        % Structure containing information about human cone case
        % Only applies when the name field has the string 'human' in it.
        sensor.human = val;
    case {'humanconetype','conetype'}
        % Blank (K) K=1 and L,M,S cone at each position
        % L=2, M=3 or S=4 (K means none)
        % Some number of cone types as cone positions.
        sensor.human.coneType = val;
    case {'humanconedensities','densities'}
        %- densities used to generate mosaic (K,L,M,S)
        sensor.human.densities = val;
    case {'humanconelocs','conexy','conelocs','xy'}
        %- xy position of the cones in the mosaic
        sensor.human.xy = val;
    case {'humanrseed','rseed'}
        % random seed for generating mosaic
        sensor.human.rSeed = val;

        % Sensor motion -  used for eye movements or camera shake
    case {'sensormovement','eyemovement'}
        % A structure with sensor motion information
        sensor.movement = val;
    case {'movementpositions','sensorpositions'}
        % Nx2 vector of (x,y) positions in deg
        sensor.movement.pos = val;
    case {'framesperposition','exposuretimesperposition','etimeperpos'}
        % Exposure frames for each (x,y) position
        % This is a vector with some number of exposures for each x,y
        % position (deg)
        sensor.movement.framesPerPosition = val;

    otherwise
        error('Unknown parameter.');
end

end

%---------------------
function sensor = sensorSetQuantization(sensor,qMethod)
%
%  sensor = sensorSetQuantization(sensor,qMethod)
%
% Set the quantization method and bit count for an image sensor array.
%
% Examples
%   sensor = sensorSetQuantization(sensor,'analog')
%   sensor = sensorSetQuantization(sensor,'10 bit')

if ~exist('qMethod','var') || isempty(qMethod), qMethod = 'analog'; end

qMethod = ieParamFormat(qMethod);
switch lower(qMethod)
    case 'analog'
        sensor.quantization.bits = [];
        sensor.quantization.method = 'analog';
    case '4bit'
        sensor.quantization.bits = 4;
        sensor.quantization.method = 'linear';
    case '8bit'
        sensor.quantization.bits = 8;
        sensor.quantization.method = 'linear';
    case '10bit'
        sensor.quantization.bits = 10;
        sensor.quantization.method = 'linear';
    case '12bit'
        sensor.quantization.bits = 12;
        sensor.quantization.method = 'linear';
    case 'sqrt'
        sensor.quantization.bits = 8;
        sensor.quantization.method = 'sqrt';
    case 'log'
        sensor.quantization.bits = 8;
        sensor.quantization.method = 'log';
    otherwise
        error('Unknown quantization method %s.',qMethod);
end

end