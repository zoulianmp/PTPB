function dose = OED(responseModel, doseCumulative, varargin)
%dose = OED(responseModel, doseCumulative, ...)
%dose = OED(responseModel, doseCumulative, options, ...)
%
% Calculates the Organ Equivalent Dose (OED) from the cumulative dose distribution data points.
%
%Where,
% responseModel can be either 'LNT', 'PlateauHall', 'LinExp', 'Competition' or 'LinPlat'.
%
% doseCumulative are the cumulative dose distribution data points as a function of dose (dose on x-axis).
%
% options is a structure of optional parameters to pass to the underlying integration and interpolation routines.
% It should be created with the struct() function as follows (with default values indicated):
%   options = struct('integration_method', 'quadv', 'tolerance', 1e-6, 'interpolation_method', 'pchip');
% The option definitions are:
%   'integration_method' - The integration method to use, can be one of 'quad', 'quadv', 'quadl', 'quadgk' or 'trapz'.
%   'tolerance' - The error tolerance parameter to use for the integration.
%   'interpolation_method' - The interpolation method to use for doseInterpolate.
%
% Extra parameters passed to OED will be passed onto the integrand functions.
% For example, to pass the organ specific sterilisation parameter alpha to the LinExp function,
% call OED as follows: y = OED('LinExp', dataPoints, alpha);
%
% The output is the integrated OED dose.
%
%Example:
% xp = 0:0.1:50;
% yp = (1+erf(10-xp))/2;
% data = [xp; yp];
% plateau_threshold = 35;
% dose = OED('PlateauHall', data, struct('integration_method', 'trapz'), plateau_threshold);
%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%    Particle Therapy Project Bergen (PTPB) - tools and models for research in
%    cancer therapy using particle beams.
%
%    Copyright (C) 2013-2014 Particle Therapy Group Bergen
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Authors: Artur Szostak <artursz@iafrica.com>, Camilla H Stokkevaag <camilla.stokkevag@ift.uib.no>

if nargin == 0
    % Print help message if no arguments are given.
    help OED;
    return;
end

% Unpack the options if there are any. Otherwise the defaults are used.
integrationMethod = 'quadv';
tolerance = 1e-6;
interpMethod = 'pchip';
if length(varargin) > 0 && isstruct(varargin{1})
    integrandParams = varargin(2:length(varargin));
    opts = varargin{1};
    if isfield(opts, 'integration_method')
        integrationMethod = opts.integration_method;
    end
    if isfield(opts, 'tolerance')
        tolerance = opts.tolerance;
    end
    if isfield(opts, 'interpolation_method')
        interpMethod = opts.interpolation_method;
    end
else
    integrandParams = varargin;
end

% Select the integrand function based on the response model.
switch responseModel
    case 'LNT'
        integrand = @(x) LNT(x, doseCumulative, interpMethod);
    case 'PlateauHall'
        integrand = @(x) PlateauHall(x, doseCumulative, interpMethod, integrandParams{:});
    case 'LinExp'
        integrand = @(x) LinExp(x, doseCumulative, interpMethod, integrandParams{:});
    case 'Competition'
        integrand = @(x) Competition(x, doseCumulative, interpMethod, integrandParams{:});
    case 'LinPlat'
        integrand = @(x) LinPlat(x, doseCumulative, interpMethod, integrandParams{:});
    otherwise
        error('Unknown response model type "%s".', responseModel);
end

% Select the integration function based on the integration method.
switch integrationMethod
    case 'quad'
        integrate = @(f, a, b) quad(f, a, b, tolerance);
    case 'quadv'
        integrate = @(f, a, b) quadv(f, a, b, tolerance);
    case 'quadl'
        integrate = @(f, a, b) quadl(f, a, b, tolerance);
    case 'quadgk'
        integrate = @(f, a, b) quadgk(f, a, b, tolerance);
    case 'trapz'
        integrate = @(f, a, b) trapzIntegrate(f, a, b, tolerance);
    otherwise
        error('Unsupported integration method "%s".', integrationMethod);
end

dose = integrate(integrand, 0, 1);
return;


function y = trapzIntegrate(f, a, b, tol)
% Simple integration method using the trapz function.

h = abs(b-a)*tol*2;  % <= initial step size
x = a:h:b;
oldy = trapz(x, f(x));
% Halve the step size and calculate again:
h = h/2;
x = a:h:b;
y = trapz(x, f(x));
% While the difference (estimate of error) is greater than the tolerance
% threshold, keep halving the step size and calculate again.
while abs(y - oldy) > tol
    oldy = y;
    h = h/2;
    x = a:h:b;
    y = trapz(x, f(x));
end
return;


function y = LNT(x, doseCumulative, interpMethod)
y = doseInterpolate(x, doseCumulative, interpMethod);
return;


function y = PlateauHall(x, doseCumulative, interpMethod, threshold)
% Check for optional threshold parameter, otherwise set it to 4 Gy.
if ~ exist('threshold')
    threshold = 4.5;
end
d = doseInterpolate(x, doseCumulative, interpMethod);
y = d .* (d < threshold) + threshold .* (d >= threshold);
return;


function y = LinExp(x, doseCumulative, interpMethod, alpha)
d = doseInterpolate(x, doseCumulative, interpMethod);
y = d.*exp(-alpha.*d);
return;


function y = Competition(x, doseCumulative, interpMethod, alpha1, beta1, alpha2, beta2, n)
% n is the number of dose fractions.
d = doseInterpolate(x, doseCumulative, interpMethod);
y = (d + beta1./alpha1.*d.^2./n).*exp(-(alpha2.*d + beta2.*d.^2./n));
return;


function y = LinPlat(x, doseCumulative, interpMethod, delta)
d = doseInterpolate(x, doseCumulative, interpMethod);
y = ((1-exp(-delta.*d))./delta);
return;
