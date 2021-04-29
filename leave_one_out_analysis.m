clear all
% disable the warning for rank-deficient design matrices. will check it manually.
warning ('off', 'stats:LinearModel:RankDefDesignMat');

%data_path = '/Users/grigori/Documents/code';
%data_file_name = 'outcome.xlsx';
[data_file_name, data_path] = uigetfile({'*.xls;*.xlsx','Excel file'},'Select the data file');

prompt = '1: linear regression; 2: stepwise linear regression; 3: generalized linear regression; 4: decision tree';
method_str = inputdlg (prompt, 'Please enter the analysis method', 1, {'1'});
if isempty (method_str)
    method_str = '1';
end
method = round (str2num (method_str{1}));
if method > 4
    disp ('Must enter a number between 1 and 4.');
    return
end
method_name = {'linear regression'; 'stepwise linear regression'; 'generalized linear regression'; 'decision tree'};


cd (data_path);
T = readtable (data_file_name, 'Sheet', 'to_analyze');
T = T (:, 2:size(T, 2)); % get rid of the first column of subject IDs
temp = T.Properties.VariableNames;
predictor_names = temp (1:length(temp) - 1);
outcome_name = temp{length (temp)};
outcome = table2array (T (:, size(T, 2)));
N = size (T, 1); % number of observations
feature_weight = NaN (N, length (predictor_names));

for i = 1:N
    fprintf ('iteration %d out of %d\n', i, N);
    train_idx = setdiff (1:N, i);
    train_data = T (train_idx, :);
    test_data = T (i, :);
    
    % train the model
    if method == 1
        model = fitlm (train_data);
    elseif method == 2
        model = stepwiselm (train_data, 'constant','upper', 'linear', 'Verbose', 0);
    elseif method == 3
        model = fitglm (train_data);
    else
        model = fitctree (train_data, outcome_name);
    end
    
    % predict the left-out score
    pred_outcome(i) = predict (model, test_data);
    
    % record the predictors that are selected (or are significant) at this iteration
    if method == 1 || method == 3 % LM or generalized LM
        % find predictors with p<0.05
        idx = find (model.Coefficients.pValue < 0.05);
        % subtract 1 from idx because the first coefficient is for the intercept
        weight_idx = idx - 1;
        weight_idx (weight_idx < 1) = [];
        feature_weight (i, weight_idx) = model.Coefficients.tStat(weight_idx+1);
    elseif method == 2 % stepwise LM
        % find predictors that are selected
        for j = 1:length (predictor_names)
            idx = find (strcmp (model.CoefficientNames, predictor_names{j}));
            if ~isempty (idx)
                feature_weight (i, j) = model.Coefficients.tStat(idx);
            end
        end
    else % classification w/ decision tree
        % find predictors with nonzero importance
        weights = predictorImportance (model);
        idx = find (weights > 0);
        feature_weight (i, idx) = weights (idx);
    end
end
pred_outcome = pred_outcome';

fprintf ('\nLeave-one-out %s on %s, performed with %d observations\n', method_name{method}, outcome_name, N);
if method < 4
    [r, p] = corrcoef (pred_outcome, outcome);
    fprintf ('Correlation between actual and predicted scores: Pearson''s r = %.4g (p = %g)\n', r(1, 2), p (1, 2));
    weight_name = 't';
else
    if isnumeric (outcome)
        acc = sum (pred_outcome == outcome) / N;
    else
        acc = sum (cellfun (@strcmp, pred_outcome, outcome)) / N;
    end
    fprintf ('\nClassification accuracy: %.2f%%\n', acc*100);
    weight_name = 'importance';
end

% average predicted scores across the iterations
feature_count = sum (~isnan (feature_weight), 1);
temp = feature_weight;
temp (isnan (temp)) = 0; % only count the iterations when the predictor was significant
feature_weight_mean = sum (temp) ./ feature_count;
feature_count_pct = feature_count / N;

important_features_idx = find (feature_count_pct > 0.05);
fprintf ('Features that are significant / selected in at least 5%% of iterations:\n');
for i = 1:length (important_features_idx)
    j = important_features_idx(i);
    fprintf ('%s (%s = %g, %.2f%% of iterations)\n', predictor_names{j}, weight_name, feature_weight_mean(j), feature_count_pct(j)*100);
end

if method < 4
    % scatterplot with regression line
    figure;
    hold on
    plot (outcome, pred_outcome, 'ko');
    [pp, s] = polyfit (outcome, pred_outcome, 1);
    plot (outcome, pp(1)*outcome+pp(2), 'k');
    axis ([min(outcome(:)) max(outcome(:)) min(pred_outcome(:)) max(pred_outcome(:))]);
    xlabel ('Actual outcome');
    ylabel ('Predicted outcome');
    plot_title = outcome_name;
    plot_title (plot_title == '_') = '-';
    title (plot_title);
    
    % save the predicted outcome values
    fp = fopen (['predicted_' outcome_name '.txt'], 'w');
    fprintf (fp, '%f\n', pred_outcome);
    fclose (fp);
    
    % run prediction on full model
    if method == 1
        fullmodel = fitlm (T);
    elseif method == 2
        fullmodel = stepwiselm (T, 'constant','upper', 'linear', 'Verbose', 0);
    elseif method == 3
        fullmodel = fitglm (T);
    end
    fprintf ('\nRunning the analysis on the full set...\n');
    disp (fullmodel);
    
    num_idx = find (fullmodel.VariableInfo.InModel & ~fullmodel.VariableInfo.IsCategorical);
    T_num = table2array (T (:, num_idx));
    if rank (T_num) < size (T_num, 2)
        fprintf ('WARNING! The design matrix is rank-deficient. Some predictors seem to be redundant. \nThis might influence the accuracy of the results.\n');
    end
    
else
    % confusion matrix
    outcome_categories = unique (outcome);
    conmatrix = confusionmat (outcome, pred_outcome ,'Order', outcome_categories);
    figure;
    imagesc (conmatrix');
    colorbar;
    set (gca, 'XTick', 1:length (outcome_categories));
    set (gca, 'YTick', 1:length (outcome_categories));
    set (gca, 'XTickLabels', outcome_categories);
    set (gca, 'YTickLabels', outcome_categories);
    xlabel ('Actual category');
    ylabel ('Predicted category');
    plot_title = outcome_name;
    plot_title (plot_title == '_') = '-';
    title (['Confusion matrix for ' plot_title]);
    disp ('Confusion matrix:');
    disp (conmatrix);
        
    
    % save the predicted outcome values
    fp = fopen (['predicted_' outcome_name '.txt'], 'w');
    if isnumeric (pred_outcome)
        fprintf (fp, '%f\n', pred_outcome);
    else
        for i = 1:length (pred_outcome)
            fprintf (fp, '%s\n', pred_outcome{i});
        end
    end
    fclose (fp);
    
    fullmodel = fitctree (T, outcome_name);
    fprintf ('Running the analysis on the full set...\n');
    fullmodel_pred = predict (fullmodel, T);
    if isnumeric (outcome)
        fullmodel_acc = sum (fullmodel_pred == outcome) / N;
    else
        fullmodel_acc = sum (cellfun (@strcmp, fullmodel_pred, outcome)) / N;
    end
    fprintf ('Classification accuracy on the full set (no leave-one-out): %.2f\n', fullmodel_acc);
    fullmodel_weights = predictorImportance (fullmodel);
    for i = 1:length (predictor_names)
        if fullmodel_weights(i) > 0
            fprintf ('%s: importance = %.2f\n', predictor_names{i}, fullmodel_weights(i));
        end
    end
end