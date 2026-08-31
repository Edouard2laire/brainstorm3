function varargout = process_evt_merge_continious( varargin )
% process_evt_merge_continious:  Merge continious, uninterrupted events
% into one event. 
%
% USAGE:  OutputFiles = process_evt_merge_continious('Run', sProcess, sInputs)

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
% Authors: Edouard Delaire, 2026

eval(macro_method);
end


%% ===== GET DESCRIPTION =====
function sProcess = GetDescription() 
    % Description the process
    sProcess.Comment     = 'Generate continuous events';
    sProcess.Category    = 'File';
    sProcess.SubGroup    = 'Events';
    sProcess.Index       = 55;
    sProcess.Description = '';
    % Definition of the input accepted by this process
    sProcess.InputTypes  = {'data', 'raw', 'matrix'};
    sProcess.OutputTypes = {'data', 'raw', 'matrix'};
    sProcess.nInputs     = 1;
    sProcess.nMinFiles   = 1;

    % Event name
    sProcess.options.combine.Comment = 'Event Names (seperated by comma)';
    sProcess.options.combine.Type    = 'text';
    sProcess.options.combine.Value   = '';

    % Ignore bad segment
    sProcess.options.ignore_bad.Comment = 'Remove bad segments';
    sProcess.options.ignore_bad.Type    = 'checkbox';
    sProcess.options.ignore_bad.Value   = 1;

    % Event name
    sProcess.options.evt_sufix.Comment = 'Event suffix';
    sProcess.options.evt_sufix.Type    = 'text';
    sProcess.options.evt_sufix.Value   = 'continuous';

    % Minimum events durations
    sProcess.options.min_duration.Comment = 'Minimum event duration: ';
    sProcess.options.min_duration.Type    = 'value';
    sProcess.options.min_duration.Value   = {30, 's', 0};

    
end


%% ===== FORMAT COMMENT =====
function Comment = FormatComment(sProcess)
    Comment = sProcess.Comment;
end


%% ===== RUN =====
function OutputFiles = Run(sProcess, sInput)
    % Return all the input files
    OutputFiles = {};   


    % ===== GET OPTIONS =====
    % Combination string
    eventNames = cellfun(@(x) strtrim(x),  strsplit(sProcess.options.combine.Value, ','),  'UniformOutput',  false);
    if isempty(eventNames)
        bst_report('Error', sProcess, [], 'Missing event names.');
        return;
    end
    % Output suffix
    evt_sufix = sProcess.options.evt_sufix.Value;
    if isempty(evt_sufix)
        evt_sufix = 'continuous';
    end

    % Ignore bad segmens 
    ignore_bad = sProcess.options.ignore_bad.Value;
    min_duration = sProcess.options.min_duration.Value{1};


    % ===== GET FILE DESCRIPTOR =====
    isRaw = strcmpi(sInput.FileType, 'raw');
    % Load the raw file descriptor
    if isRaw
        DataMat = in_bst_data(sInput.FileName, {'Time', 'F'});
        sFile = DataMat.F;
        sFile.Time = DataMat.Time;
    else
        DataMat = in_bst_data(sInput.FileName, {'TIme', 'Events'});
        sFile.events = DataMat.Events;
        sFile.epochs = [];
    end

    % Process only continuous files
    if ~isempty(sFile.epochs)
        bst_report('Error', sProcess, sInput, 'This function can only process continuous recordings (no epochs). Skipping File...');
        return;
    end

    % If no markers are present in this file
    if isempty(sFile.events)
        bst_report('Warning', sProcess, sInput, 'This file does not contain any event. Skipping File...');
        return;
    end

    event_idx = zeros(1, length(eventNames));
    for iEvt = 1:length(eventNames)
        idx = find(strcmp({sFile.events.label}, eventNames{iEvt}));
        if isempty(idx)
            bst_report('Warning', sProcess, sInput, sprintf('Unable to find event %s',  eventNames{iEvt}));
            continue;
        end
        
        event_idx(iEvt) = idx;
    end

    event_idx = event_idx(event_idx > 0);
    sEvents = sFile.events(event_idx);
    
    % Create binary mask
    mask = event2mask(sFile.Time, sEvents);

    % Remove bad period
    if ignore_bad
        bad_events = find(cellfun(@(x)contains(x, 'bad') , {sFile.events.label}));
        if ~isempty(bad_events)
            sBadEvents = sFile.events(bad_events);
            bad_mask = ~event2mask(sFile.Time, sBadEvents);
    
            mask = mask .* bad_mask;
        end
    end

    % Recreate continuous events
    newEvents = mask2events(sFile.Time, mask, sEvents, min_duration, evt_sufix);
    
    sFile.events = [sFile.events , newEvents];

    % ===== SAVE RESULT =====
    % Report results
    if isRaw
        DataMat.F = sFile;
    else
        DataMat.Events = sFile.events;
    end
    bst_save(file_fullpath(sInput.FileName), DataMat, 'v6', 1);



    % Return all the input files
    OutputFiles{end+1} = sInput.FileName;
end


function mask = event2mask(Time, sEvents)

    mask = false(length(sEvents), length(Time));
    for iEvt = 1:length(sEvents)
        
        for iTime = 1:size(sEvents(iEvt).times, 2)
            idx_time = panel_time('GetTimeIndices', Time, sEvents(iEvt).times(:, iTime));
            mask(iEvt, idx_time) = 1;
        end
    end

end

function newEvents = mask2events(Time, mask, sEvents, min_duration, evt_sufix)
    
    newEvents = sEvents;
    isIncluded = true(1, length(sEvents));

    for iEvt = 1:length(sEvents)
        
        newEvents(iEvt).label = sprintf('%s/%s', newEvents(iEvt).label, evt_sufix);

        tmp = diff(mask(iEvt,:)); 
        start_segment = find(tmp == 1) + 1; 
        end_segment   = find(tmp == -1);

        if length(start_segment) ==  length(end_segment) -1
            start_segment = [1 start_segment];
        end     
        if length(start_segment) ==  length(end_segment) +1
            end_segment = [ end_segment length(sData.Time)];
        end  
        
        new_times  = [ Time(start_segment) ;  Time(end_segment)  ];
        
        evt_durations = new_times(2,:) - new_times(1,:);
        
        isIncluded(iEvt) = any(evt_durations >= min_duration);

        newEvents(iEvt).times  = new_times(:, evt_durations >= min_duration);
        newEvents(iEvt).epochs = ones(1, size(newEvents(iEvt).times, 2));
    end

    newEvents = newEvents(isIncluded);
end

