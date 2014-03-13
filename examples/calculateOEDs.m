function result = calculateOEDs(filename, integration_method, integration_tolerance)
%function result = calculateOEDs(filename, integration_method, integration_tolerance)


% The following table remaps the names in the DVH files to standard ones:
%
%               Name in file          Name to map to
organnames = {
                'BODY',               'Body',
                'Cribriform plate',   'CribriformPlate',
                'CribiformPlate',     'CribriformPlate',
  };

% The following table maps different parameters to use for different model calculations.
%
%            The name of the    Threshold        Alpha        Competition model parameters
%            organ used in      parameter for    parameter                                  integrations
%            the DVH files.     PlateauHall.     for LinExp.  alpha1  beta1  alpha2  beta2     (n)
organtable = {
              {'Stomach',            4,           0.149,      0,      0,     0,      0,      1},
              {'Colon',              4,           0.24,       0,      0,     0,      0,      1},
              {'Liver',              4,           0.487,      0,      0,     0,      0,      1},
              {'Lungs',              4,           0.129,      0,      0,     0,      0,      1},
              {'Bladder',            4,           1.592,      0,      0,     0,      0,      1},
              {'Thyroid',            4,           0.033,      0,      0,     0,      0,      1},
              {'Prostate',           4,           0.804,      0,      0,     0,      0,      1},
  };


% Build structures to map parameters more easily in the subsequent code.
organmap = {};
for n = 1:length(organtable)
  organmap{n*2-1} = organtable{n}{1};
  organmap{n*2  } = struct('threshold', organtable{n}{2}, 'alpha', organtable{n}{3},
                           'alpha1', organtable{n}{4}, 'beta1', organtable{n}{5},
                           'alpha2', organtable{n}{6}, 'beta2', organtable{n}{7},
                           'integrations', organtable{n}{8});
end
organmap = struct(organmap{:});

organnamemap = struct(organnames{:});


% Load the data from file.
if ~ exist('filename')
  error('No data file name given.');
end
data = load(filename, 'DVH_data');


% Setup default for parameters that were not given.
if ~ exist('integration_method')
    integration_method = 'quad';
end
if ~ exist('integration_tolerance')
    integration_tolerance = 1e-3;
end


% Process the organ structures:
doseResults = {};
resultCount = 1;
organs = data.DVH_data.structures;
for n = 1:length(organs)
  s = organs{n};
  % Try map the name to a standard one.
  if isfield(organnamemap, s.structName)
    s.structName = getfield(organnamemap, s.structName);
  end

  % Check if we can handle this organ.
  if ~ isfield(organmap, s.structName)
    continue;
  end
  if ~ isfield(s, 'dose')
    warning('The dose field could not be found so %s will be skipped.', s.structName);
    continue;
  end
  if ~ isfield(s, 'ratioToTotalVolume')
    warning('The ratioToTotalVolume field could not be found so %s will be skipped.', s.structName);
    continue;
  end
  if length(s.dose) == 0
    warning('The dose field is empty so %s will be skipped.', s.structName);
    continue;
  end
  if length(s.ratioToTotalVolume) == 0
    %NOTE: hacking the data to recover ratioToTotalVolume. Not clear if this procedure is correct!
    if ~ isfield(s, 'structureVolume')
      warning('The ratioToTotalVolume field is empty so %s will be skipped.', s.structName);
      continue;
    end
    warning('The ratioToTotalVolume field is empty so will use structureVolume for the %s instead.', s.structName);
    extraError = abs(s.structureVolume(1) - s.volume) / s.volume;
    s.ratioToTotalVolume = s.structureVolume / s.structureVolume(1);
  end
  if length(size(s.dose)) ~= length(size(s.ratioToTotalVolume))
    warning('The dose and ratioToTotalVolume fields are not the same size so %s will be skipped.', s.structName);
    continue;
  end
  if size(s.dose) ~= size(s.ratioToTotalVolume)
    warning('The dose and ratioToTotalVolume fields are not the same size so %s will be skipped.', s.structName);
    continue;
  end

  printf('Processing %s\n', s.structName);

  params = getfield(organmap, s.structName);
  threshold = params.threshold;
  alpha = params.alpha;
  alpha1 = params.alpha1;
  beta1 = params.beta1;
  alpha2 = params.alpha2;
  beta2 = params.beta2;
  integrations = params.integrations;

  % Rescale the volume fraction to ratio if set as percent.
  if max(s.ratioToTotalVolume) > 1
    s.ratioToTotalVolume = s.ratioToTotalVolume / 100;
  end
  datapoints = [s.dose; s.ratioToTotalVolume];

  % Here we perform the calculations and fill in the results. We try both linear
  % and pchip interpolation methods and vary the tolerance to get and estimate of
  % the numerical uncertainty.
  opts{1} = struct('integration_method', integration_method, 'tolerance', integration_tolerance, 'interpolation_method', 'pchip');
  opts{2} = struct('integration_method', integration_method, 'tolerance', integration_tolerance, 'interpolation_method', 'linear');
  opts{3} = struct('integration_method', integration_method, 'tolerance', integration_tolerance*10, 'interpolation_method', 'pchip');
  opts{4} = struct('integration_method', integration_method, 'tolerance', integration_tolerance*10, 'interpolation_method', 'linear');
  responseModels = {'LNT', 'PlateauHall', 'LinExp', 'Competition'};
  modelResults = {};
  for k = 1:length(responseModels)
    responseModel = responseModels{k};
    switch responseModel
      case 'LNT'
        oed = @(opts) OED(responseModel, datapoints, opts);
      case 'PlateauHall'
        oed = @(opts) OED(responseModel, datapoints, opts, threshold);
      case 'LinExp'
        oed = @(opts) OED(responseModel, datapoints, opts, alpha);
      case 'Competition'
        oed = @(opts) OED(responseModel, datapoints, opts, alpha1, beta1, alpha2, beta2, integrations);
      otherwise
        error('Unsupported response model "%s".', responseModel);
    end
    doses = cellfun(oed, opts);  % apply oed to each set of options.
    dose = doses(1);   % select the best estimate for the dose.
    doseUncertainty = std(doses);  % estimate the uncertainty in the dose.
    if exist('extraError')
      doseUncertainty = sqrt(doseUncertainty^2 + (dose*extraError)^2);
    end
    printf('Calculated dose for %s = %g +/- %g\n', responseModel, dose, doseUncertainty);
    fflush(stdout);

    modelResults{k} = struct('dose', dose, 'doseUncertainty', doseUncertainty);
  end
  resultsRow = {};
  for k = 1:length(responseModels)
    resultsRow{2*k-1} = responseModels{k};
    resultsRow{2*k} = modelResults{k};
  end
  doseResults{resultCount} = s.structName;
  resultCount = resultCount + 1;
  doseResults{resultCount} = struct(resultsRow{:});
  resultCount = resultCount + 1;
end

result = struct(doseResults{:});
