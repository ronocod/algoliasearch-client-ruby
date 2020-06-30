module Algolia
  module Search
    # Class Index
    class Index
      include CallType
      include Helpers
      extend Forwardable

      attr_reader :index_name, :transporter, :config

      def_delegators :@transporter, :read, :write

      # Initialize an index
      #
      # @param index_name [String] name of the index
      # @param transporter [nil, Object] transport object used for the connection
      # @param config [nil, Config] a Config object which contains your APP_ID and API_KEY
      #
      def initialize(index_name, transporter, config)
        @index_name  = index_name
        @transporter = transporter
        @config      = config
      end

      # # # # # # # # # # # # # # # # # # # # #
      # MISC
      # # # # # # # # # # # # # # # # # # # # #

      # Wait the publication of a task on the server.
      # All server task are asynchronous and you can check with this method that the task is published.
      #
      # @param task_id the id of the task returned by server
      # @param time_before_retry the time in milliseconds before retry (default = 100ms)
      # @param opts contains extra parameters to send with your query
      #
      def wait_task(task_id, time_before_retry = Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts = {})
        loop do
          status = get_task_status(task_id, opts)
          if status == 'published'
            return
          end
          sleep(time_before_retry / 1000)
        end
      end

      # Check the status of a task on the server.
      # All server task are asynchronous and you can check the status of a task with this method.
      #
      # @param task_id the id of the task returned by server
      # @param opts contains extra parameters to send with your query
      #
      def get_task_status(task_id, opts = {})
        res    = read(:GET, path_encode('/1/indexes/%s/task/%s', @index_name, task_id), {}, opts)
        status = get_option(res, 'status')
        status
      end

      # Delete the index content
      #
      # @param opts contains extra parameters to send with your query
      #
      def clear_objects(opts = {})
        write(:POST, path_encode('/1/indexes/%s/clear', @index_name), {}, opts)
      end

      # Delete the index content and wait for operation to finish
      #
      # @param opts contains extra parameters to send with your query
      #
      def clear_objects!(opts = {})
        res     = write(:POST, path_encode('/1/indexes/%s/clear', @index_name), opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      def delete(opts = {})
        write(:DELETE, path_encode('/1/indexes/%s', @index_name), opts)
      end

      def delete!(opts = {})
        res     = write(:DELETE, path_encode('/1/indexes/%s', @index_name), opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      def delete_replica(replica_name, opts = {})
        # TODO
      end

      # Find object by the given condition.
      #
      # Options can be passed in request_options body:
      #  - query (string): pass a query
      #  - paginate (bool): choose if you want to iterate through all the
      # documents (true) or only the first page (false). Default is true.
      # The function takes a block to filter the results from search query
      # Usage example:
      #  index.find_object({'query' => '', 'paginate' => true}) {|obj| obj.key?('company') and obj['company'] == 'Apple'}
      #
      # @param opts contains extra parameters to send with your query
      #
      # @return [Hash|AlgoliaHttpError] the matching object and its position in the result set
      #
      def find_object(opts = {})
        paginate = true
        page     = 0

        query = opts[:query] || ''
        opts.delete(:query)

        if opts.has_key? :paginate
          paginate = opts[:paginate]
        end

        opts.delete(:paginate)

        loop do
          opts[:page] = page
          res         = search(query, opts)

          if block_given?
            res['hits'].each_with_index do |hit, i|
              if yield(hit)
                return {
                  object: hit,
                  position: i,
                  page: page
                }
              end
            end
          end

          has_next_page = page + 1 < res['nbPages']
          if !paginate || !has_next_page
            raise AlgoliaHttpError.new(404, 'Object not found')
          end

          page += 1
        end
      end

      #
      # Retrieve the given object position in a set of results.
      #
      # @param [Array] objects the result set to browse
      # @param [String] object_id the object to look for
      #
      # @return [Integer] position of the object, or -1 if it's not in the array
      #
      def self.get_object_position(objects, object_id)
        hits = get_option(objects, 'hits')
        hits.find_index { |hit| get_option(hit, 'objectID') == object_id } || -1
      end

      # # # # # # # # # # # # # # # # # # # # #
      # INDEXING
      # # # # # # # # # # # # # # # # # # # # #

      def get_object(object_id, opts = {})
        read(:GET, path_encode('/1/indexes/%s/%s', @index_name, object_id), {}, opts)
      end

      def get_objects(object_ids, opts = {})
        request_options        = opts
        attributes_to_retrieve = get_option(request_options, 'attributesToRetrieve')
        request_options.delete(:attributesToRetrieve)

        requests = []
        object_ids.each do |object_id|
          request = {indexName: @index_name, objectID: object_id.to_s}

          if attributes_to_retrieve
            request[:attributesToRetrieve] = attributes_to_retrieve
          end

          requests.push(request)
        end

        read(:POST, '/1/indexes/*/objects', {'requests': requests}, opts)
      end

      def find_objects
        # TODO
      end

      # Override the content of an object
      #
      # @param object [Hash] the object to save
      # @param opts [Hash] contains extra parameters to send with your query
      #
      def save_object(object, opts = {})
        save_objects([object], opts)
      end

      # Override the content of an object and wait for operation to finish
      #
      # @param object [Hash] the object to save
      # @param opts [Hash] contains extra parameters to send with your query
      #
      def save_object!(object, opts = {})
        res     = save_objects([object], opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      # Override the content of several objects
      #
      # @param objects the array of objects to save
      # @param opts contains extra parameters to send with your query
      #
      def save_objects(objects, opts = {})
        request_options    = opts
        generate_object_id = request_options[:auto_generate_object_id_if_not_exist] || false
        request_options.delete(:auto_generate_object_id_if_not_exist)
        if generate_object_id
          batch(build_batch('addObject', objects), request_options)
        else
          batch(build_batch('updateObject', objects, true), request_options)
        end
      end

      # Override the content of several objects and wait for operation to finish
      #
      # @param objects the array of objects to save
      # @param opts contains extra parameters to send with your query
      #
      def save_objects!(objects, opts = {})
        request_options    = opts
        generate_object_id = request_options[:auto_generate_object_id_if_not_exist] || false
        request_options.delete(:auto_generate_object_id_if_not_exist)
        res                = if generate_object_id
          batch(build_batch('addObject', objects), request_options)
        else
          batch(build_batch('updateObject', objects, true), request_options)
        end
        task_id            = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, request_options)
        res
      end

      def partial_update_object(object, opts = {})
        partial_update_objects([object], opts)
      end

      def partial_update_object!(object, opts = {})
        res     = partial_update_objects([object], opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      def partial_update_objects(objects, opts = {})
        generate_object_id = false
        request_options    = opts
        if get_option(request_options, 'createIfNotExists')
          generate_object_id = true
          request_options.delete(:createIfNotExists)
        end

        if generate_object_id
          batch(build_batch('partialUpdateObject', objects), request_options)
        else
          batch(build_batch('partialUpdateObjectNoCreate', objects), request_options)
        end
      end

      def partial_update_objects!(objects, opts = {})
        generate_object_id = false
        request_options    = opts
        if get_option(request_options, 'createIfNotExists')
          generate_object_id = true
          request_options.delete(:createIfNotExists)
        end

        res     = if generate_object_id
          batch(build_batch('partialUpdateObject', objects), request_options)
        else
          batch(build_batch('partialUpdateObjectNoCreate', objects), request_options)
        end
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, request_options)
        res
      end

      def delete_object(object_id, opts = {})
        delete_objects([object_id], opts)
      end

      def delete_object!(object_id, opts = {})
        res     = delete_objects([object_id], opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, request_options)
        res
      end

      def delete_objects(object_ids, opts = {})
        objects = object_ids.map do |object_id|
          {objectID: object_id}
        end
        batch(build_batch('deleteObject', objects), opts)
      end

      def delete_objects!(object_ids, opts = {})
        objects = object_ids.map do |object_id|
          {objectID: object_id}
        end
        res     = batch(build_batch('deleteObject', objects), opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, request_options)
        res
      end

      def delete_by(filters, opts = {})
        write(:POST, path_encode('/1/indexes/%s/deleteByQuery', @index_name), filters, opts)
      end

      # Send a batch request
      #
      # @param request [Hash] hash containing the requests to batch
      # @param opts contains extra parameters to send with your query
      #
      def batch(request, opts = {})
        write(:POST, path_encode('/1/indexes/%s/batch', @index_name), request, opts)
      end

      # Send a batch request and wait for operation to finish
      #
      # @param request [Hash] hash containing the requests to batch
      # @param opts contains extra parameters to send with your query
      #
      def batch!(request, opts = {})
        res     = write(:POST, path_encode('/1/indexes/%s/batch', @index_name), request, opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      # # # # # # # # # # # # # # # # # # # # #
      # QUERY RULES
      # # # # # # # # # # # # # # # # # # # # #

      def get_rule(object_id, opts = {})
        # TODO
      end

      def save_rule(rule, opts = {})
        # TODO
      end

      def save_rules(rules, opts = {})
        # TODO
      end

      def clear_rules(opts = {})
        # TODO
      end

      def delete_rule(object_id, opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # SYNONYMS
      # # # # # # # # # # # # # # # # # # # # #

      def get_synonym(object_id, opts = {})
        # TODO
      end

      def save_synonym(synonym, opts = {})
        # TODO
      end

      def save_synonyms(synonyms, opts = {})
        # TODO
      end

      def clear_synonyms(opts = {})
        # TODO
      end

      def delete_synonym(object_id, opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # BROWSING
      # # # # # # # # # # # # # # # # # # # # #

      def browse(query, opts = {})
        # TODO
      end

      def browse_objects(opts = {})
        ObjectIterator.new(@transporter, @index_name, opts)
      end

      def browse_rules(opts = {})
        # TODO
      end

      def browse_synonyms(opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # REPLACING
      # # # # # # # # # # # # # # # # # # # # #

      def replace_all_objects(objects, opts = {})
        # TODO
      end

      def replace_all_rules(rules, opts = {})
        # TODO
      end

      def replace_all_synonyms(synonyms, opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # SEARCHING
      # # # # # # # # # # # # # # # # # # # # #

      # Perform a search on the index
      #
      # @param query the full text query
      # @param opts contains extra parameters to send with your query
      #
      # @return Algolia::Response
      #
      def search(query, opts = {})
        read(:POST, path_encode('/1/indexes/%s/query', @index_name), {'query': query}, opts)
      end

      def search_for_facet_values(facet_name, facet_query, opts = {})
        read(:POST, path_encode('/1/indexes/%s/facets/%s/query', @index_name, facet_name),
             {'facetQuery': facet_query}, opts)
      end

      def search_rules(query, opts = {})
        # TODO
      end

      def search_synonyms(query, opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # SETTINGS
      # # # # # # # # # # # # # # # # # # # # #

      def get_settings(opts = {})
        opts[:getVersion] = '2'

        read(:GET, path_encode('/1/indexes/%s/settings', @index_name), {}, opts)
      end

      def set_settings(settings, opts = {})
        write(:PUT, path_encode('/1/indexes/%s/settings', @index_name), settings, opts)
      end

      def set_settings!(settings, opts = {})
        res     = write(:PUT, path_encode('/1/indexes/%s/settings', @index_name), settings, opts)
        task_id = get_option(res, 'taskID')
        wait_task(task_id, Defaults::WAIT_TASK_DEFAULT_TIME_BEFORE_RETRY, opts)
        res
      end

      # # # # # # # # # # # # # # # # # # # # #
      # EXISTS
      # # # # # # # # # # # # # # # # # # # # #

      def exists(opts = {})
        # TODO
      end

      # # # # # # # # # # # # # # # # # # # # #
      # PRIVATE
      # # # # # # # # # # # # # # # # # # # # #

      private

      # Check the passed object to determine if it's an array
      #
      # @param object [Object]
      #
      def check_array(object)
        raise ArgumentError, 'argument must be an array of objects' unless object.is_a?(Array)
      end

      # Check the passed object
      #
      # @param object [Object]
      # @param in_array [Boolean] whether the object is an array or not
      #
      def check_object(object, in_array = false)
        case object
        when Array
          raise ArgumentError, in_array ? 'argument must be an array of objects' : 'argument must not be an array'
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          raise ArgumentError, "argument must be an #{'array of' if in_array} object, got: #{object.inspect}"
        end
      end

      # Check if passed object has a objectID
      #
      # @param object [Object]
      # @param object_id [String]
      #
      def get_object_id(object, object_id = nil)
        check_object(object)
        object_id ||= object[:objectID] || object['objectID']
        raise ArgumentError, "Missing 'objectID'" if object_id.nil?
        object_id
      end

      # Build a batch request
      #
      # @param action [String] action to perform on the engine
      # @param objects [Array] objects on which build the action
      # @param with_object_id [Boolean] if set to true, check if each object has an objectID set
      #
      def build_batch(action, objects, with_object_id = false)
        check_array(objects)
        {
          requests: objects.map do |object|
            check_object(object, true)
            request            = {action: action, body: object}
            request[:objectID] = get_object_id(object).to_s if with_object_id
            request
          end
        }
      end
    end
  end
end