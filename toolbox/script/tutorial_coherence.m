function tutorial_coherence(tutorial_dir, reports_dir)
% TUTORIAL_COHERENCE: Script that runs the Brainstorm corticomuscular coherence tutorial
% https://neuroimage.usc.edu/brainstorm/Tutorials/CorticomuscularCoherence
%
% INPUTS: 
%    - tutorial_dir : Directory where the SubjectCMC.zip file has been unzipped
%    - reports_dir  : Directory where to save the execution report (instead of displaying it)

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c) University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Author: Raymundo Cassani & Francois Tadel, 2022

% Output folder for reports
if (nargin < 2) || isempty(reports_dir) || ~isfolder(reports_dir)
    reports_dir = [];
end
% You have to specify the folder in which the tutorial dataset is unzipped
if (nargin == 0) || isempty(tutorial_dir) || ~file_exist(tutorial_dir)
    error('The first argument must be the full path to the dataset folder.');
end

% Protocol name
ProtocolName = 'TutorialCMC';
% Subject name
SubjectName = 'Subject01';
% Channel selection
emg_channel = 'EMGlft';   % Name of EMG channel
meg_sensor  = 'MRC21';    % MEG sensor over the left motor-cortex (MRC21)
% Coherence parameters
cohmeasure = 'mscohere'; % Magnitude-squared Coherence|C|^2 = |Cxy|^2/(Cxx*Cyy)
win_length = 0.5;        % 500ms
overlap    = 50;         % 50%
maxfreq    = 80;         % 80Hz

% Build the path of the files to import
MriFilePath = fullfile(tutorial_dir, 'SubjectCMC', 'SubjectCMC.mri');
MegFilePath = fullfile(tutorial_dir, 'SubjectCMC', 'SubjectCMC.ds');
% Check if the folder contains the required files
if ~file_exist(MriFilePath) || ~file_exist(MegFilePath)
    error(['The folder ' tutorial_dir ' does not contain the folder from the file SubjectCMC.zip.']);
end


%% ===== CREATE PROTOCOL =====
% Start brainstorm without the GUI
if ~brainstorm('status')
    brainstorm nogui
end
% Delete existing protocol
gui_brainstorm('DeleteProtocol', ProtocolName);
% Create new protocol
gui_brainstorm('CreateProtocol', ProtocolName, 0, 0);
% Start a new report
bst_report('Start');
% Reset colormaps
bst_colormaps('RestoreDefaults', 'meg');
% Hide scouts
panel_scout('SetScoutShowSelection', 'none');


%% ===== IMPORT ANATOMY =====
% Process: Import MRI
bst_process('CallProcess', 'process_import_mri', [], [], ...
    'subjectname', SubjectName, ...
    'mrifile',     {MriFilePath, 'ALL'}, ...
    'nas',         [0, 0, 0], ...
    'lpa',         [0, 0, 0], ...
    'rpa',         [0, 0, 0], ...
    'ac',          [0, 0, 0], ...
    'pc',          [0, 0, 0], ...
    'ih',          [0, 0, 0]);
% Process: Generate head surface
bst_process('CallProcess', 'process_generate_head', [], [], ...
    'subjectname', SubjectName, ...
    'nvertices',   10000, ...
    'erodefactor', 0, ...
    'fillfactor',  2);


%% ===== LINK TO RAW FILE AND DISPLAY REGISTRATION =====
% Process: Create link to raw files
sFileRaw = bst_process('CallProcess', 'process_import_data_raw', [], [], ...
    'subjectname',  SubjectName, ...
    'datafile',     {MegFilePath, 'CTF'}, ...
    'channelalign', 1);
% Process: Snapshot: Sensors/MRI registration
bst_process('CallProcess', 'process_snapshot', sFileRaw, [], ...
    'target',   1, ...  % Sensors/MRI registration
    'modality', 1, ...  % MEG (All)
    'orient',   1, ...  % left
    'Comment',  'MEG/MRI Registration');
% Process: Convert to continuous (CTF): Continuous
bst_process('CallProcess', 'process_ctf_convert', sFileRaw, [], ...
    'rectype', 2);  % Continuous


%% ===== EVENT MARKERS =====
% Process: Read from channel
sFileRaw = bst_process('CallProcess', 'process_evt_read', sFileRaw, [], ...
    'stimchan',     'Stim', ...
    'trackmode',    1, ...  % Value: detect the changes of channel value
    'zero',         0, ...
    'min_duration', 12);
% Load all Event group labels
DataMat = in_bst_data(sFileRaw.FileName, 'F');
eventList = {DataMat.F.events.label};
% Labels for Event groups to keep
eventKeep = cellfun(@(c)sprintf('U%d',c), num2cell([1:6, 8:25]), 'UniformOutput', 0);
% Find useless Events
eventDelete = setdiff(eventList, eventKeep);
% Process: Delete events
sFileRaw = bst_process('CallProcess', 'process_evt_delete', sFileRaw, [], ...
    'eventname', strjoin(eventDelete, ', '));
% Process: Merge events
sFileRaw = bst_process('CallProcess', 'process_evt_merge', sFileRaw, [], ...
    'evtnames', strjoin(eventKeep, ', '), ...
    'newname',  'Left');


%% ===== REMOVAL OF POWER LINE ARTIFACTS =====
% Process: Notch filter: 50Hz 100Hz 150Hz
sFileRawNotch = bst_process('CallProcess', 'process_notch', sFileRaw, [], ...
    'freqlist',    [50, 100, 150], ...
    'sensortypes', 'MEG, EMG', ...
    'read_all',    1);
% Process: Power spectrum density (Welch)
sFilesPsd = bst_process('CallProcess', 'process_psd', [sFileRaw, sFileRawNotch], [], ...
    'timewindow',  [0 330], ...
    'win_length',  10, ...
    'win_overlap', 50, ...
    'clusters',    {}, ...
    'sensortypes', 'MEG, EMG', ...
    'edit', struct(...
         'Comment',    'Power', ...
         'TimeBands',  [], ...
         'Freqs',      [], ...
         'ClusterFuncTime', 'none', ...
         'Measure',    'power', ...
         'Output',     'all', ...
         'SaveKernel', 0));
% Process: Snapshot: Frequency spectrum
bst_process('CallProcess', 'process_snapshot', sFilesPsd, [], ...
    'target',   10, ...  % Frequency spectrum
    'Comment',  'Power spectrum density');


%% ===== EMG PRE-PROCESSING =====
% Process: High-pass:10Hz
sFileRawNotchHigh = bst_process('CallProcess', 'process_bandpass', sFileRawNotch, [], ...
    'sensortypes', 'EMG', ...
    'highpass',    10, ...
    'lowpass',     0, ...
    'tranband',    0, ...
    'attenuation', 'strict', ...  % 60dB
    'ver',         '2019', ...  % 2019
    'mirror',      0, ...
    'read_all',    0);
% Process: Absolute values
sFileRawNotchHighAbs = bst_process('CallProcess', 'process_absolute', sFileRawNotchHigh, [], ...
    'sensortypes', 'EMG');
% Process: Delete folders
bst_process('CallProcess', 'process_delete', [sFileRawNotch, sFileRawNotchHigh], [], ...
    'target', 2);  % Delete folders


%% ===== MEG PRE-PROCESSING =====
% Process: Detect eye blinks
bst_process('CallProcess', 'process_evt_detect_eog',  sFileRawNotchHighAbs, [], ...
    'channelname', 'EOG', ...
    'timewindow',  [0 330], ...
    'eventname',   'blink');
% Process: SSP EOG: blink
bst_process('CallProcess', 'process_ssp_eog', sFileRawNotchHighAbs, [], ...
    'eventname',   'blink', ...
    'sensortypes', 'MEG', ...
    'usessp',      1, ...
    'select',      1);
% Process: Snapshot: SSP projectors
bst_process('CallProcess', 'process_snapshot', sFileRawNotchHighAbs, [], ...
    'target',  2, ...  % SSP projectors
    'Comment', 'SSP projectors');

% Process: Detect other artifacts
bst_process('CallProcess', 'process_evt_detect_badsegment', sFileRawNotchHighAbs, [], ...
    'timewindow',  [0 330], ...
    'sensortypes', 'MEG', ...
    'threshold',   3, ...  % 3
    'isLowFreq',   1, ...
    'isHighFreq',  1);
% Process: Rename event (1-7Hz > bad_1-7Hz)
bst_process('CallProcess', 'process_evt_rename', sFileRawNotchHighAbs, [], ...
    'src',  '1-7Hz', ...
    'dest', 'bad_1-7Hz');
% Process: Rename event (40-240Hz > bad_40-240Hz)
bst_process('CallProcess', 'process_evt_rename', sFileRawNotchHighAbs, [], ...
    'src',  '40-240Hz', ...
    'dest', 'bad_40-240Hz');


%% ===== IMPORTING DATA EPOCHS =====
% Process: Import MEG/EEG: Events
sFilesEpochs = bst_process('CallProcess', 'process_import_data_event', sFileRawNotchHighAbs, [], ...
    'subjectname',   SubjectName, ...
    'condition',     '', ...
    'eventname',     'Left', ...
    'timewindow',    [0, 330], ...
    'epochtime',     [0, 7.9992], ...
    'split',         1, ...
    'createcond',    0, ...
    'ignoreshort',   1, ...
    'usectfcomp',    1, ...
    'usessp',        1, ...
    'freq',          [], ...
    'baseline',      'all', ...
    'blsensortypes', 'MEG');
% Process: Snapshot: Recordings time series
bst_process('CallProcess', 'process_snapshot', sFilesEpochs(1), [], ...
    'type',           'data', ...  % Recordings time series
    'modality',       1, ... % MEG (All)
    'rowname',        meg_sensor, ...
    'Comment',        ['Epoch #1: ' meg_sensor]);
% Process: Snapshot: Recordings time series
bst_process('CallProcess', 'process_snapshot', sFilesEpochs(1), [], ...
    'type',           'data', ...  % Recordings time series
    'modality',       10, ... % EMG
    'rowname',        '', ...
    'Comment',        'Epoch #1: EMG');


%% ===== COHERENCE: EMG x MEG =====
% Process: Coherence 1xN [2021]
sFileCoh1N = bst_process('CallProcess', 'process_cohere1_2021', {sFilesEpochs.FileName}, [], ...
    'timewindow',   [], ...
    'src_channel',  emg_channel, ...
    'dest_sensors', 'MEG', ...
    'includebad',   0, ...
    'removeevoked', 0, ...
    'cohmeasure',   'mscohere', ...
    'win_length',   win_length, ...
    'overlap',      overlap, ...
    'maxfreq',      maxfreq, ...
    'outputmode',   'avgcoh');  % Average cross-spectra of input files (one output file)
% Process: Add tag
sFileCoh1N = bst_process('CallProcess', 'process_add_tag', sFileCoh1N, [], ...
    'tag',      'MEG sensors', ...
    'output',   1);  % Add to file name
% Set selected sensors
bst_figures('SetSelectedRows', {meg_sensor});
% Process: Snapshot: Frequency spectrum
bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
    'target',   10, ...  % Frequency spectrum
    'freq',     17.58, ...
    'Comment',  ['MSC ' emg_channel '  x MEG']);
% Process: Snapshot: Frequency spectrum
bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
    'target',   10, ...  % Frequency spectrum
    'freq',     17.58, ...
    'rowname',  meg_sensor, ...
    'Comment',  ['MSC ' emg_channel ' x ', meg_sensor]);
% Process: Snapshot: Recordings topography (one time)
bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
    'type',     'topo', ...  % Recordings topography (one time)
    'modality', 1, ...  % MEG (All)
    'freq',     17.58, ...
    'Comment',  ['2D sensor cap MSC ' emg_channel ' x MEG']);


%% ===== COHERENCE: EMG x MEG (FREQUENCY BAND) =====
% Process: Group in time or frequency bands
sFileCoh1NBand = bst_process('CallProcess', 'process_tf_bands', sFileCoh1N, [], ...
    'isfreqbands', 1, ...
    'freqbands',   {'cmc_band', '15, 20', 'mean'}, ...
    'istimebands', 0, ...
    'timebands',   '', ...
    'overwrite',   0);
% Process: Snapshot: Recordings topography (one time)
bst_process('CallProcess', 'process_snapshot', sFileCoh1NBand, [], ...
    'type',     'topo', ...  % Recordings topography (one time)
    'modality', 1, ...  % MEG (All)
    'Comment',  ['2D topography MSC 15-20Hz ' emg_channel ' x MEG']);


%% ===== SOURCE ESTIMATION =====
% Process: Segment MRI with CAT12
bst_process('CallProcess', 'process_segment_cat12', [], [], ...
    'subjectname', SubjectName, ...
    'nvertices',   15000, ...
    'tpmnii',      {'', 'Nifti1'}, ...
    'sphreg',      1, ...
    'vol',         1, ...
    'extramaps',   0, ...
    'cerebellum',  0);
% Process: Compute covariance (noise or data)
bst_process('CallProcess', 'process_noisecov', sFileRawNotchHighAbs, [], ...
    'baseline',       [18, 29], ...
    'datatimewindow', [], ...
    'sensortypes',    'MEG', ...
    'target',         1, ...  % Noise covariance     (covariance over baseline time window)
    'dcoffset',       1, ...  % Block by block, to avoid effects of slow shifts in data
    'identity',       0, ...
    'copycond',       1, ...
    'copysubj',       0, ...
    'copymatch',      0, ...
    'replacefile',    1);  % Replace

% Process: Compute head model (surface)
bst_process('CallProcess', 'process_headmodel', sFilesEpochs(1).FileName, [], ...
    'Comment',      'Overlapping spheres (surface)', ...
    'sourcespace',  1, ... % Cortex
    'meg',          3);    % Overlapping spheres
% Process: Compute sources [2018]
bst_process('CallProcess', 'process_inverse_2018', sFilesEpochs(1).FileName, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'MN: MEG (surface)', ...
         'InverseMethod',  'minnorm', ...
         'InverseMeasure', 'amplitude', ...
         'SourceOrient',   {{'fixed'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'reg', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'fixed', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG'}}));
% Process: Compute sources [2018]
bst_process('CallProcess', 'process_inverse_2018', sFilesEpochs(1).FileName, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'MN: MEG (surface)', ...
         'InverseMethod',  'minnorm', ...
         'InverseMeasure', 'amplitude', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'reg', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'fixed', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG'}}));

% Process: Compute head model (volume)
bst_process('CallProcess', 'process_headmodel', sFilesEpochs(1).FileName, [], ...
    'Comment',     'Overlapping spheres (volume)', ...
    'sourcespace', 2, ...  % MRI volume
    'volumegrid',  struct(...
         'Method',        'isotropic', ...
         'nLayers',       17, ...
         'Reduction',     3, ...
         'nVerticesInit', 4000, ...
         'Resolution',    0.005, ...
         'FileName',      []), ...
    'meg',         3 );  % Overlapping spheres
% Process: Compute sources [2018]
bst_process('CallProcess', 'process_inverse_2018', sFilesEpochs(1).FileName, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'MN: MEG (volume)', ...
         'InverseMethod',  'minnorm', ...
         'InverseMeasure', 'amplitude', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'reg', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'fixed', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG'}}));


%% ===== COHERENCE: EMG x SOURCES =====
% Process: Select data files
sFilesRecEmg = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname',   SubjectName, ...
    'condition',     '', ...
    'tag',           'Left', ...
    'includebad',    0, ...
    'includeintra',  0, ...
    'includecommon', 0);
% Coherence between EMG signal and sources (for different source types)
sourceTypes = {'(surface)(Constr)', '(surface)(Unconstr)', '(volume)(Unconstr)'};
for ix = 1 :  length(sourceTypes)
    sourceType = sourceTypes{ix};
    % Process: Select results files
    sFilesResMeg = bst_process('CallProcess', 'process_select_files_results', [], [], ...
        'subjectname',   SubjectName, ...
        'condition',     '', ...
        'tag',           sourceType, ...
        'includebad',    0, ...
        'includeintra',  0, ...
        'includecommon', 0);
    % Process: Coherence AxB [2021]
    sFileCoh1N = bst_process('CallProcess', 'process_cohere2_2021', sFilesRecEmg, sFilesResMeg, ...
        'timewindow',   [], ...
        'src_channel',  emg_channel, ...
        'dest_scouts',  {}, ...
        'scoutfunc',    1, ...  % Mean
        'scouttime',    2, ...  % After
        'removeevoked', 0, ...
        'cohmeasure',   cohmeasure, ...
        'win_length',   win_length, ...
        'overlap',      overlap, ...
        'maxfreq',      maxfreq, ...
        'outputmode',   'avgcoh');  % Average cross-spectra of input files (one output file)
    % Process: Add tag
    sFileCoh1N = bst_process('CallProcess', 'process_add_tag', sFileCoh1N, [], ...
        'tag',           sourceType, ...
        'output',        1);  % Add to file name
    % View surface
    if ~isempty(strfind(sourceType, 'surface'))
        % Process: Snapshot: Sources (one time)
        bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
            'type',        'sources', ...  % Sources (one time)
            'orient',      3, ...  % top
            'threshold',   0, ...
            'surfsmooth',  30, ...
            'freq',        14.65, ...
            'Comment',     ['MSC 14.65Hz ',  sourceType]);
    % View volume
    elseif ~isempty(strfind(sourceType, 'volume'))
        % Process: Snapshot: Sources (MRI Viewer)
        bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
            'type',        'mriviewer', ...  % MRI viewer
            'threshold',   0, ...
            'freq',        14.65, ...
            'mni',         [26, -11, 73], ...
            'Comment',     ['MSC 14.65Hz ',  sourceType]);
    end
end


%% ===== COHERENCE: EMG x SCOUTS (BEFORE) =====
% Process: Select data files
sFilesRecEmg = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname',   SubjectName, ...
    'condition',     '', ...
    'tag',           'Left', ...
    'includebad',    0, ...
    'includeintra',  0, ...
    'includecommon', 0);
% Only performed for (surface)(Constrained)
sourceType = '(surface)(Constr)';
sFilesResSrfUnc = bst_process('CallProcess', 'process_select_files_results', [], [], ...
    'subjectname',   SubjectName, ...
    'condition',     '', ...
    'tag',           sourceType, ...
    'includebad',    0, ...
    'includeintra',  0, ...
    'includecommon', 0);
% Process: Coherence AxB [2021]
sFileCoh1N = bst_process('CallProcess', 'process_cohere2_2021', sFilesRecEmg, sFilesResSrfUnc, ...
    'timewindow',   [], ...
    'src_channel',  emg_channel, ...
    'dest_scouts',  {'Schaefer_100_17net', {'Background+FreeSurfer_Defined_Medial_Wall L', 'Background+FreeSurfer_Defined_Medial_Wall R', 'ContA_IPS_1 L', 'ContA_IPS_1 R', 'ContA_PFCl_1 L', 'ContA_PFCl_1 R', 'ContA_PFCl_2 L', 'ContA_PFCl_2 R', 'ContB_IPL_1 R', 'ContB_PFCld_1 R', 'ContB_PFClv_1 L', 'ContB_PFClv_1 R', 'ContB_Temp_1 R', 'ContC_Cingp_1 L', 'ContC_Cingp_1 R', 'ContC_pCun_1 L', 'ContC_pCun_1 R', 'ContC_pCun_2 L', 'DefaultA_IPL_1 R', 'DefaultA_PFCd_1 L', 'DefaultA_PFCd_1 R', 'DefaultA_PFCm_1 L', 'DefaultA_PFCm_1 R', 'DefaultA_pCunPCC_1 L', 'DefaultA_pCunPCC_1 R', 'DefaultB_IPL_1 L', 'DefaultB_PFCd_1 L', 'DefaultB_PFCd_1 R', 'DefaultB_PFCl_1 L', 'DefaultB_PFCv_1 L', 'DefaultB_PFCv_1 R', 'DefaultB_PFCv_2 L', 'DefaultB_PFCv_2 R', 'DefaultB_Temp_1 L', 'DefaultB_Temp_2 L', 'DefaultC_PHC_1 L', 'DefaultC_PHC_1 R', 'DefaultC_Rsp_1 L', 'DefaultC_Rsp_1 R', 'DorsAttnA_ParOcc_1 L', 'DorsAttnA_ParOcc_1 R', 'DorsAttnA_SPL_1 L', 'DorsAttnA_SPL_1 R', 'DorsAttnA_TempOcc_1 L', 'DorsAttnA_TempOcc_1 R', 'DorsAttnB_FEF_1 L', 'DorsAttnB_FEF_1 R', 'DorsAttnB_PostC_1 L', 'DorsAttnB_PostC_1 R', 'DorsAttnB_PostC_2 L', 'DorsAttnB_PostC_2 R', 'DorsAttnB_PostC_3 L', 'LimbicA_TempPole_1 L', 'LimbicA_TempPole_1 R', 'LimbicA_TempPole_2 L', 'LimbicB_OFC_1 L', 'LimbicB_OFC_1 R', 'SalVentAttnA_FrMed_1 L', 'SalVentAttnA_FrMed_1 R', 'SalVentAttnA_Ins_1 L', 'SalVentAttnA_Ins_1 R', 'SalVentAttnA_Ins_2 L', 'SalVentAttnA_ParMed_1 L', 'SalVentAttnA_ParMed_1 R', 'SalVentAttnA_ParOper_1 L', 'SalVentAttnA_ParOper_1 R', 'SalVentAttnB_IPL_1 R', 'SalVentAttnB_PFCl_1 L', 'SalVentAttnB_PFCl_1 R', 'SalVentAttnB_PFCmp_1 L', 'SalVentAttnB_PFCmp_1 R', 'SomMotA_1 L', 'SomMotA_1 R', 'SomMotA_2 L', 'SomMotA_2 R', 'SomMotA_3 R', 'SomMotA_4 R', 'SomMotB_Aud_1 L', 'SomMotB_Aud_1 R', 'SomMotB_Cent_1 L', 'SomMotB_Cent_1 R', 'SomMotB_S2_1 L', 'SomMotB_S2_1 R', 'SomMotB_S2_2 L', 'SomMotB_S2_2 R', 'TempPar_1 L', 'TempPar_1 R', 'TempPar_2 R', 'TempPar_3 R', 'VisCent_ExStr_1 L', 'VisCent_ExStr_1 R', 'VisCent_ExStr_2 L', 'VisCent_ExStr_2 R', 'VisCent_ExStr_3 L', 'VisCent_ExStr_3 R', 'VisCent_Striate_1 L', 'VisPeri_ExStrInf_1 L', 'VisPeri_ExStrInf_1 R', 'VisPeri_ExStrSup_1 L', 'VisPeri_ExStrSup_1 R', 'VisPeri_StriCal_1 L', 'VisPeri_StriCal_1 R'}}, ...
    'scoutfunc',    1, ...  % Mean
    'scouttime',    1, ...  % Before
    'removeevoked', 0, ...
    'cohmeasure',   cohmeasure, ...
    'win_length',   win_length, ...
    'overlap',      overlap, ...
    'maxfreq',      maxfreq, ...
    'outputmode',   'avgcoh');  % Average cross-spectra of input files (one output file)
% Process: Add tag
sFileCoh1N = bst_process('CallProcess', 'process_add_tag', sFileCoh1N, [], ...
    'tag',           sourceType, ...
    'output',        1);  % Add to file name
% Highlight scout of interest
bst_figures('SetSelectedRows', 'SomMotA_4 R');
% Process: Snapshot: Frequency spectrum
bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
    'target',   10, ...  % Frequency spectrum
    'freq',     14.65, ...
    'Comment',  ['MSC ,' sourceType, ' Before']);
% Process: Snapshot: Connectivity matrix
bst_process('CallProcess', 'process_snapshot', sFileCoh1N, [], ...
    'type',     'connectimage', ...  % Connectivity matrix
    'freq',     14.65, ...
    'Comment',  ['MSC 14.65Hz,' sourceType, ' Before']);


%% ===== SAVE REPORT =====
% Save and display report
ReportFile = bst_report('Save', []);
if ~isempty(reports_dir) && ~isempty(ReportFile)
    bst_report('Export', ReportFile, reports_dir);
else
    bst_report('Open', ReportFile);
end

disp([10 'DEMO> Corticomuscular coherence tutorial completed' 10]);

