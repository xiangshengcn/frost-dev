function [xdot] = firstOrderDynamics(obj, t, x, controller, params, logger)
    % calculate the dynamical equation of the first order dynamical system
    %
    % Parameters:
    % t: the time instant @type double
    % x: the states @type colvec
    % controller: the controller @type Controller
    % params: the parameter structure @type struct
    % logger: the data logger object @type SimLogger
    %
    % Return values:
    % xdot: the derivative of the system states @type colvec
    
    % extract the state variables into x and dx
    nx = obj.numState;
    
    % store time and states into object private data for future use
    obj.t_ = t;
    obj.states_.x = x;
    
    % compute the mass matrix and drift vector (internal dynamics)
    M = calcMassMatrix(obj, x);
    Fv = calcDriftVector(obj, x);
    
    
    
    
    %% get the external input
    f_ext_name = fieldnames(obj.Inputs.External);
    if ~isempty(f_ext_name)              % if external inputs are defined
        n_ext = length(f_ext_name);
        % initialize the Gv_ext vector
        Gv_ext = zeros(nx,1);
        for i=1:n_ext   
            f_name = f_ext_name{i};
            % get the Gvec function object
            % g_fun = obj.Gvec.External.(f_name);
            % call the callback function to get the external input
            f_ext = obj.ExternalInputFun(obj, f_name, t, x, params, logger);
            % compute the Gvec, and add it up
            Gv_ext = Gv_ext + feval(obj.GvecName_.External.(f_name),x,f_ext);
            
            % store the external inputs into the object private data
            obj.inputs_.External.(f_name) = f_ext;
        end
    end
    
    
    %% holonomic constraints
    h_cstr_name = fieldnames(obj.HolonomicConstraints);
    if ~isempty(h_cstr_name)           % if holonomic constraints are defined
        h_cstr = struct2array(obj.HolonomicConstraints);
        n_cstr = length(h_cstr);
        % determine the total dimension of the holonomic constraints
        cdim = sum([h_cstr.Dimension]);
        % initialize the Jacobian matrix
        Je = zeros(cdim,nx);
        Jedot = zeros(cdim,nx);
        
        idx = 1;
        for i=1:n_cstr
            cstr = h_cstr(i);
            cstr_indices = idx:idx+cstr.Dimension-1;
            % calculate the Jacobian
            if cstr.DerivativeOrder == 2
                [Jh,dJh] = calcJacobian(cstr,x);
                Je(cstr_indices,:) = Jh;
                Jedot(cstr_indices,:) = dJh;
            else
                [Jh] = calcJacobian(cstr,x);
                Je(cstr_indices,:) = Jh;
                Jedot(cstr_indices,:) = Jh;
            end
	    tol = 1e-3;
            if norm(Jh*x) > tol
                warning('The holonomic constraint %s violated.', h_cstr_name{i});
            end     
            idx = idx + cstr.Dimension;
        end  
    else
        Je = [];
        Jedot = [];
    end
    
    
    %% calculate the constrained vector fields and control inputs
    control_name = fieldnames(obj.Inputs.Control);
    if ~isempty(control_name)
        Be = feval(obj.GmapName_.Control.(control_name{1}),q);
        Ie    = eye(nx);
        
        if isempty(Je)
            vfc = M\(Fv + Gv_ext);
            gfc = M\Be;
        else
        
            XiInv = Jedot * (M \ transpose(Je));
            % compute vector fields
            % f(x)
            vfc = M \ ((Ie - transpose(Je) * (XiInv \ (Jedot / M))) * (Fv + Gv_ext));
            
            
            % g(x)
            gfc =  M \ (Ie - transpose(Je)* (XiInv \ (Jedot / M))) * Be;
        end
        % compute control inputs
        u = calcControl(controller, t, x, vfc, gfc, obj, params, logger);
        
        Gv_u = Be*u;
        obj.inputs_.Control.(control_name{1}) = u;
    end
    %% calculate constraint wrench of holonomic constraints
    Gv = Gv_ext + Gv_u;
    % Calculate constrained forces
    Gv_c = zeros(nx,1);
    if ~isempty(h_cstr_name)
        lambda = -XiInv \ (Jedot * (M \ (Fv + Gv)));
        % the constrained wrench inputs
        Gv_c = transpose(Je)*lambda;
        
        % extract and store
        idx = 1;
        for i=1:n_cstr           
            cstr = h_cstr(i);
            hval.(h_cstr_name{i}) = calcConstraint(cstr,x);
            cstr_indices = idx:idx+cstr.Dimension-1;
            input_name = cstr.InputName;
            obj.inputs_.ConstraintWrench.(input_name) = lambda(cstr_indices);
            idx = idx + cstr.Dimension;
        end 
    end
    
    Gv = Gv + Gv_c;
    
    % the system dynamics
    xdot = M \ (Fv + Gv);
    obj.states_.dx = xdot;
    
    if ~isempty(logger)
        calc = logger.calc;

        calc.t       = t;
        calc.states  = obj.states_;
        calc.inputs  = obj.inputs_;
        calc.hval    = hval;

        logger.calc  = calc;
    end
end