function varargout = process_segment_siam( varargin )
% PROCESS_SEGMENT_SIAM: Run the segmentation of a T1 MRI with SIAM.
%
% USAGE:     OutputFiles = process_segment_siam('Run',     sProcess, sInputs)
%         [isOk, errMsg] = process_segment_siam('Compute', iSubject, iAnatomy=[default], nVertices, isSphReg, isExtraMaps, isInteractive)
%                          process_segment_siam('ComputeInteractive', iSubject, iAnatomy)

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
% Authors: Francois Tadel, 2019-2023

eval(macro_method);
end


%% ===== GET DESCRIPTION =====
function sProcess = GetDescription() %#ok<DEFNU>
    % Description the process
    sProcess.Comment     = 'Segment MRI with SIAM';
    sProcess.Category    = 'Custom';
    sProcess.SubGroup    = {'Import', 'Import anatomy'};
    sProcess.Index       = 31;
    sProcess.Description = 'https://neuroimage.usc.edu/brainstorm/Tutorials/SegCAT12';
    % Definition of the input accepted by this process
    sProcess.InputTypes  = {'import'};
    sProcess.OutputTypes = {'import'};
    sProcess.nInputs     = 1;
    sProcess.nMinFiles   = 0;
    % Option: Subject name
    sProcess.options.subjectname.Comment = 'Subject name:';
    sProcess.options.subjectname.Type    = 'subjectname';
    sProcess.options.subjectname.Value   = '';

end


%% ===== FORMAT COMMENT =====
function Comment = FormatComment(sProcess) %#ok<DEFNU>
    Comment = sProcess.Comment;
end


%% ===== RUN =====
function OutputFiles = Run(sProcess, sInputs) %#ok<DEFNU>
    OutputFiles = {};

    % Get subject name
    SubjectName = file_standardize(sProcess.options.subjectname.Value);
    if isempty(SubjectName)
        bst_report('Error', sProcess, [], 'Subject name is empty.');
        return;
    end

    % Get subject 
    [sSubject, iSubject] = bst_get('Subject', SubjectName);
    if isempty(iSubject)
        bst_report('Error', sProcess, [], ['Subject "' SubjectName '" does not exist.']);
        return
    end
    % Call processing function
    [isOk, errMsg] = Compute(iSubject, [], 1);
    % Handling errors
    if ~isOk
        bst_report('Error', sProcess, [], errMsg);
    elseif ~isempty(errMsg)
        bst_report('Warning', sProcess, [], errMsg);
    end
    % Return an empty structure
    OutputFiles = {'import'};
end


%% ===== COMPUTE CAT12 SEGMENTATION =====
function [isOk, errMsg] = Compute(iSubject, iAnatomy, isInteractive)
    errMsg = '';
    isOk = 0;
    % Initialize SPM12+CAT12
    [ensureRes,  errMsg] = bst_plugin('Ensure', 'siam');
    if ~isempty(errMsg)
        error(errMsg);
        return;
    end

    % Retrieve info of container
    [errMsg, containerInfo] = bst_containers('GetContainerInfo', 'bst_siam');
    if ~isempty(errMsg) || ~containerInfo.isRunning
        return
    end

    % ===== GET SUBJECT =====
    % Get subject 
    [sSubject, iSubject] = bst_get('Subject', iSubject);
    if isempty(sSubject)
        errMsg = 'Subject does not exist.';
        return
    end
    % Check if a MRI is available for the subject
    if isempty(sSubject.Anatomy)
        errMsg = ['No MRI available for subject "' sSubject.Name '".'];
        return
    end
    % Get default MRI if not specified
    if isempty(iAnatomy)
        iAnatomy = sSubject.iAnatomy;
    end
    
    % ===== VERIFY FIDUCIALS IN MRI =====
    % Load MRI file
    T1FileBst = sSubject.Anatomy(iAnatomy).FileName;
    sMri = in_mri_bst(T1FileBst);
    % If the SCS transformation is not defined: compute MNI transformation to get a default one
    if isempty(sMri) || ~isfield(sMri, 'SCS') || ~isfield(sMri.SCS, 'NAS') || ~isfield(sMri.SCS, 'LPA') || ~isfield(sMri.SCS, 'RPA') || (length(sMri.SCS.NAS)~=3) || (length(sMri.SCS.LPA)~=3) || (length(sMri.SCS.RPA)~=3) || ~isfield(sMri.SCS, 'R') || isempty(sMri.SCS.R) || ~isfield(sMri.SCS, 'T') || isempty(sMri.SCS.T)
        % Issue warning
        errMsg = 'Missing NAS/LPA/RPA: Computing the MNI normalization to get default positions.'; 
        % Compute MNI normalization
        [sMri, errNorm] = bst_normalize_mni(T1FileBst);
        % Handle errors
        if ~isempty(errNorm)
            errMsg = [errMsg 10 'Error trying to compute the MNI normalization: ' 10 errNorm 10 ...
                'Missing fiducials: the surfaces cannot be aligned with the MRI.'];
        end
    end
    % A vox2ras matrix must be present in the MRI for running CAT12
    sMri = mri_add_world(T1FileBst, sMri);

    % ===== SAVE MRI AS NII =====
    bst_progress('text', 'Saving temporary files...');
    % Create temporay folder for CAT12 output
    TmpDir = containerInfo.volumes{1,1};
    % Save MRI in .nii format
    subjid = strrep(sSubject.Name, '@', '');
    NiiFile = bst_fullfile(TmpDir, [subjid, '.nii']);
    out_mri_nii(sMri, NiiFile);
    % If a "world transformation" was not available in the MRI in the database, it was set to a default when saving to .nii
    % Let's reload this file to get the transformation matrix, it will be used when importing the results
    if ~isfield(sMri, 'InitTransf') || isempty(sMri.InitTransf) || isempty(find(strcmpi(sMri.InitTransf(:,1), 'vox2ras')))
        % Load again the file, with the default vox2ras transformation
        [tmp, vox2ras] = in_mri_nii(NiiFile, 0, 0, 0);
        % Prepare the history of transformations
        if ~isfield(sMri, 'InitTransf') || isempty(sMri.InitTransf)
            sMri.InitTransf = cell(0,2);
        end
        % Add this transformation in the MRI
        sMri.InitTransf(end+1,[1 2]) = {'vox2ras', vox2ras};
        % Save modification on hard drive
        bst_save(file_fullpath(T1FileBst), sMri, 'v7');
    end
    
    % ===== Launch Siam
    command = ['siam-pred -i ' , bst_fullfile(containerInfo.volumes{1,2}, [subjid, '.nii']),  ...
                          ' -device cpu', ...
                          ' --verbose', ...
                          ' -nbthread 1', ...
                          ' >',  bst_fullfile(containerInfo.volumes{1,2}, 'log.txt') ];
    
    errMsg = bst_containers('ExecInContainer', containerInfo.name, command);



    % Delete temporary folder
    % file_delete(TmpDir, 1, 1);
    % Remove logo
    bst_progress('removeimage');
    % Return success
    isOk = 1;
end



%% ===== COMPUTE/INTERACTIVE =====
function ComputeInteractive(iSubject, iAnatomy) %#ok<DEFNU>
    % Get inputs
    if (nargin < 2) || isempty(iAnatomy)
        iAnatomy = [];
    end
    % Ask for number of vertices
    nVertices = java_dialog('input', 'Number of vertices on the cortex surface:', 'CAT12 segmentation', [], '15000');
    if isempty(nVertices)
        return
    end
    nVertices = str2double(nVertices);
    % Ask for volume atlases
    [isVolumeAtlases, isCancel] = java_dialog('confirm', ['Compute anatomical parcellations?' 10 10 ...
        ' - AAL3', 10 ...
        ' - Anatomy v3', 10 ...
        ' - CoBrALab' 10 ...
        ' - Hammers' 10 ... 
        ' - IBSR', 10 ...
        ' - JulichBrain v2', 10 ...
        ' - LPBA40' 10 ...
        ' - Mori', 10 ...
        ' - Neuromorphometrics' 10 ...
        ' - Schaefer2018', 10 10], 'CAT12 MRI segmentation');
    if isCancel
        return
    end
    % Ask for cortical maps (not for default anatomy)
    if (iSubject > 0)
        [isExtraMaps, isCancel] = java_dialog('confirm', ['Compute cortical maps?' 10 10 ...
            ' - Cortical thickness', 10 ...
            ' - Gyrification index', 10 ...
            ' - Sulcal depth', 10 10], 'CAT12 MRI segmentation');
        if isCancel
            return
        end
    else
        isExtraMaps = 0;
    end
    % Open progress bar
    bst_progress('start', 'CAT12', 'CAT12 MRI segmentation...');
    % TPM atlas, preferably from SPM plugin
    TpmNii = bst_get('SpmTpmAtlas', 'SPM');
    % Run CAT12
    isInteractive = 1;
    isSphReg = 1;
    isCerebellum = 0;
    [isOk, errMsg] = Compute(iSubject, iAnatomy, nVertices, isInteractive, TpmNii, isSphReg, isVolumeAtlases, isExtraMaps, isCerebellum);
    % Error handling
    if ~isOk
        bst_error(errMsg, 'CAT12 MRI segmentation', 0);
    elseif ~isempty(errMsg)
        java_dialog('msgbox', ['Warning: ' errMsg]);
    end
    % Close progress bar
    bst_progress('stop');
end
