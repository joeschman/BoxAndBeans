function record_myo_data
	% This file allows to record simultanuos movement data from 2 DOFs from the Myo
	% It is based on Code from Dr. Janne Hahne.
	%
	% 1) Install and start Myo Connect from Thalmics Labs, conncet one or two
	% MYOs, sync MYO(s) to avoid sleep-mode
	%
	% 2) Run this m file, the communication to the MYOs should be initialised,
	% the MYO(s) should vibrate shortly
	%
	%% add paths

	addpath('../plotting/');
	addpath('../myo/');

	%% Settings:

	N_myos = 1; % number of MYOs to use (1 or 2)
	f_powerline = 50; % choose 50 or 60 Hz depending on your region
	port = 3333; % port for TCP-IP connection

	% fix values ----------------------------------------------------
	width   = 0.12;  % time window width of a data point in seconds
	overlap = 0.04;  % overlap of time windows in seconds
	sF      = 200;   % sampling frequency of the myo
	N_window  = width * sF;    % Time window samples
	N_overlap = overlap * sF;  % Overlap samples
	blocksize = 8;             % blockzise from MyoTcpBridge
	% ---------------------------------------------------------------

	% Init

	% close potentially existing old instances of "myDaqObj"
	if exist('myDaqObj')
		disp('closing old MyoTcpBridge');
		myDaqObj.delete();
	end

	% create a DaqThalmicsTcpBridge object, automaticly start MyoTcpBridge.exe
	% and establish connection:
	myDaqObj = DaqThalmicsTcpBridge(N_myos,true,port);

	% create filter object aginst powerline noise: 
	fiterObj = combFilter(myDaqObj.fs,f_powerline);

	%% make a calibration recording to estimate the maximal activation
	myDaqObj.startDaq();

	N_Dims    = 8;
	win_len   = 100;
	X_meanAbs = zeros(win_len, N_Dims);
	X_logVar  = zeros(win_len, N_Dims);

	figH      = myFigure
	axis 'auto y'; 
	plot_targetIntensityCurves(figH, win_len, 'calibration: relax and hand close');
	fprintf('calibration recording to estimate the maximal activation'); pause; fprintf(' -> RUN\n')



	for i=0:win_len
			percentage = i/win_len * 100;
			if i > 0
					[X_meanAbs(i,:), X_logVar(i,:), prev_data] = read_data_calc_feats(myDaqObj, fiterObj, prev_data);
					plot(i, mean(X_meanAbs(i,:)), 'ro');
					plot(i, mean(X_logVar(i,:)), 'go');
					axis 'auto y';
			else
					[~, ~, prev_data] = read_data_calc_feats(myDaqObj, fiterObj, []);
			end
	end

	max_meanAbs = max(X_meanAbs(:));
	max_logVar = max(X_logVar(:));

	myDaqObj.stopDaq();

	fprintf('record data for training'); pause; fprintf(' -> RUN\n');
	%% record data for training
	myDaqObj.startDaq();

	postures = {'no movement', 'hand open', 'hand close', 'supination', 'pronation', ...
			'hand open + supination', 'hand open + pronation', ...
			'hand close + supination', 'hand close + pronation'};

	N_Posts   = numel(postures);
	win_len   = 100; % 60 for 3 seconds contraction; old: 100 = 4.8s contrac
	pause_len = 20;
	N_Data    = N_Posts*(win_len + pause_len);
	% allocate space for the raw data
	X_raw     = zeros((N_window-N_overlap)*N_Data, N_Dims);
	% allocate space for the features 
	X_meanAbs = zeros(N_Data, N_Dims);
	X_logVar  = zeros(N_Data, N_Dims);

	% generate the trainings curve
	act_curve = generate_myo_training_curve(postures, win_len, pause_len);

	curr_time_window = round(win_len * 2);


	% loop over the postures
	for p = 1:N_Posts
			% plot the target intensity curve
			%plot_targetIntensityCurves(figH, win_len, postures{p});
			%pause;
			if p == 1
					if ~ishandle(figH)
					%if ~isvalid(figH)
							figH      = myFigure;
					end
					
					leftPoint  = 1;
					rightPoint = 1 + round(0.75*curr_time_window);
					hold off;
					plot(leftPoint:rightPoint, act_curve(leftPoint:rightPoint), '-b');
					hold on;
					axis([leftPoint rightPoint 0 1]);
					title(postures{p});
			end
			fprintf('next posture: %s', postures{p}); pause; fprintf(' -> RUN\n');
			
			% record data for each posture
			for i=0:(win_len + pause_len)
					if i > 0            
							offset    = (p-1)*(win_len + pause_len);
							currPoint = offset + i;
							[X_meanAbs(currPoint,:), X_logVar(currPoint,:), prev_data, new_data] = read_data_calc_feats(myDaqObj, fiterObj, prev_data);
							% save the raw data
							X_raw((N_window-N_overlap)*(currPoint-1)+1:(N_window-N_overlap)*currPoint, :) = new_data';
							% normalize the features
							%X_meanAbs(currPoint,:) = X_meanAbs(currPoint,:)./max_meanAbs);
							%X_logVar(currPoint,:) = X_logVar(currPoint,:)./max_logVar;
							% plot the mean activation
							%plot(i, mean(X_meanAbs(offset+i,:)/max_meanAbs), 'ro');
							plot(currPoint, mean(X_logVar(currPoint,:))/max_logVar, 'go');
							
							% shift the window
							if i == win_len
									leftPoint  = currPoint - round(0.25*curr_time_window);
									rightPoint = min(currPoint + round(0.75*curr_time_window), numel(act_curve));
									hold off;
									plot(leftPoint:rightPoint, act_curve(leftPoint:rightPoint));
									hold on;
									% plot also the old movement recordings
									old_x_vals = mean(X_logVar(leftPoint:currPoint, :),2)./max_logVar;
									plot(leftPoint:currPoint, old_x_vals, 'go');
									axis([leftPoint rightPoint 0 1]);
									if p+1 <= N_Posts
											title(['next: ' postures{p+1}]);
									else
											title(['next: ' postures{1}]);
									end
									%pause;
							end
							
							
					else
							[~, ~, prev_data] = read_data_calc_feats(myDaqObj, fiterObj, []);
					end
			end
	end

	% post process the activation curve such that it can be use as the target
	% variable: rescale it to be between 0 and 1
	targets = (act_curve - 0.1) / 0.6;
	targets(:,1) = targets;
	targets(:,2) = targets;

	% define label values for the degrees of freedom
	%          ha op; ha cl; sup;  pro; op sup; op pro; cl sup; cl pro
	dof = [0 0;  1 0;  -1 0; 0 1; 0 -1;    1 1;   1 -1;   -1 1; -1 -1];
	for p=2:N_Posts
			offset = (p-1)*(win_len + pause_len);
			targets(offset+1:offset+win_len,1) = targets(offset+1:offset+win_len,1) .* dof(p,1);
			targets(offset+1:offset+win_len,2) = targets(offset+1:offset+win_len,2) .* dof(p,2);
	end




	% 
	% % generate the target variable
	% Labels = [];
	% cutoff = round(0.3*win_len);
	% cutoff_end = win_len - cutoff;
	% 
	% Labels = [Labels; repmat([dof(1,1) dof(1,2)], win_len, 1)]; % no movement
	% for p=2:N_Posts
	%     Labels = [Labels; linspace(0, dof(p,1), cutoff)' linspace(0, dof(p,2), cutoff)']; 
	%     Labels = [Labels; repmat([dof(p,1) dof(p,2)], cutoff_end-cutoff, 1)];
	%     Labels = [Labels; linspace(dof(p,1), 0, cutoff)' linspace(dof(p,2), 0, cutoff)']; 
	% end
	% 
	% % for a test, cut the first and last 30%
	% X_cut = [];
	% Labels_cut = [];
	% for p=1:N_Posts    
	%     posts_offset = (p-1)*win_len;
	%     X_cut = [X_cut; X_logVar(posts_offset+cutoff+1:posts_offset+cutoff_end,:)];
	%     Labels_cut = [Labels_cut; p*ones(cutoff_end-cutoff,1)];
	% end


	myDaqObj.stopDaq()



	%% close everything in a clean way
	myDaqObj.delete();
end
