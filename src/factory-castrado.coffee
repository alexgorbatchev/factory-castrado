_ = require 'lodash'


asyncForEach = (array, handler, callback) ->
	length = array.length
	index = -1

	processNext = ->
		index++
		if index < length
			item = array[index]
			handler item, processNext
		else
			callback()

	processNext()


factories = {}

define = (name, model, options, attributes) ->
	# Handle argument combinations
	switch arguments.length
		when 1
			# Only 1 parameter: (options)
			options = name
			param = undefined for param in [model, name]

		when 2
			# Params are (name, options)
			if model.attributes? or model.extends?
				options = model
				model = undefined
			# Params are (name, model) - no attributes, "blank"
			else
				attributes = model
				model = undefined

		when 3
			# Params are (name, options, attributes)
			if model.attributes? or model.extends? or model.model?
				[options, attributes] = [model, options] 
				model = undefined

			# Params are (name, model, attributes)
			if typeof model is 'function'
				attributes = options
				options = undefined

			# Params are (name, model, options)
			# (Nothing to do)

	model = options?.model ? model
	attributes = options?.attributes ? attributes
	name = options?.name ? name
	associations = options?.associations ? {}

	# This factory extends another
	if options?.extends
		parent = factories[options.extends]
		# Set model if not already set
		model ?= parent.model
		# Get copy of parent attributes, and merge
		parentAttrs = _.clone parent.attributes
		_.defaults attributes, parentAttrs
		# Get copy of parent associations, and merge
		parentAssoc = _.clone parent.associations
		_.defaults associations, parentAssoc


	factories[name] = 
		model: model
		attributes: attributes
		associations: associations

build = (name, userAttrs, callback) ->
	if typeof userAttrs is 'function'
		[callback, userAttrs] = [userAttrs, {}]
	factory = factories[name]

	model = factory.model

	associations = _.clone factory.associations
	attributes = _.clone factory.attributes
	_.extend attributes, userAttrs

	setters = []

	# Compute associations
	asyncForEach _.keys(associations), (assocName, cb) ->
		assoc = associations[assocName]

		assocFactory = factories[assoc.factory ? assocName]
		setterFn = assoc.setter
		getterFn = assoc.getter ? (obj) -> return obj.id
		key = assoc.key
		switch assoc.type ? 'id'
			when 'id'
				key ?= assocName + '_id'
				do ->
					_key = key
					setterFn ?= (obj, val) -> 
						obj.set _key, val


			when 'ids[]'
				key ?= assocName + '_ids'
				do ->
					_key = key
					setterFn ?= (obj, val) ->
						current = obj.get _key
						unless val in current
							obj.set key, current.push(val)


		# Pass in override association objects
		if attributes[assocName]
			_obj = associations[assocName] = attributes[assocName]
			delete attributes[assocName]
			_val = getterFn _obj

			assembledSetter = do ->
				val = _val
				return ((obj)-> 
					# console.log 'SETTER', _val
					setterFn(obj, _val)
				)
			
			setters.push assembledSetter

			cb()
		# Already manually set
		else if attributes[key] and assoc.type is 'id'
			cb()

		# Build the associated object
		else
			create assoc.factory, (_obj) ->
				associations[assocName] = _obj
				val = getterFn _obj

				assembledSetter = do ->
					_val = val
					return ((obj)-> 
						# console.log 'SETTER', _val
						setterFn(obj, _val)
					)

				setters.push assembledSetter
				cb()

	, ->

		asyncForEach _.keys(attributes), (key, cb) ->
			fn = attributes[key]
			# Lazy attribute
			if typeof fn is 'function'
				fn (computedVal) ->
					attributes[key] = computedVal
					cb()
			else
				cb()
		, ->
			object = new model attributes

			for own key, val of attributes
				object.set key, val

			for own key, val of associations
				object[key] = val

			object.once 'setAssoc', ->
				for setter in setters
					setter?(object)

			# 	setter() for setter in setters
			object.trigger 'setAssoc'

			callback(object)


create = (name, userAttrs, callback) ->
	if typeof userAttrs is 'function'
		[callback, userAttrs] = [userAttrs, {}]

	build name, userAttrs, (doc) ->
		doc.create (err) ->
			if err then throw err

			callback doc

Factory = create
Factory.define = define
Factory.build = build
Factory.create = create


module.exports = Factory