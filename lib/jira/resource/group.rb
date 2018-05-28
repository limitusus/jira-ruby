module JIRA
  module Resource

    class GroupFactory < JIRA::BaseFactory # :nodoc:
    end

    class Group < JIRA::Base
      has_many :members, class: JIRA::Resource::User, attribute_key: 'values'

      # The class methods are never called directly, they are always
      # invoked from a BaseFactory subclass instance.
      def self.all(client, options = {})
        max_results = 100_000
        params = { maxResults: max_results }
        response = client.get(collection_for_all_path(client) + '?' + hash_to_query_string(params))
        json = parse_json(response.body)
        if collection_attributes_are_nested
          json = json[endpoint_name.pluralize]
        end
        json['groups'].map do |attrs|
          self.new(client, {:attrs => attrs}.merge(options))
        end
      end

      # Only for self.all()
      def self.collection_for_all_path(client, prefix='/')
        client.options[:rest_base_path] + prefix + 'groups/picker'
      end

      # Returns the singular path for the resource with the given key.
      def self.singular_path(client, key, prefix = '/')
        collection_path(client, prefix) + '?groupname=' + key
      end

      def self.paging_path(client, key, prefix = '/')
        client.options[:rest_base_path] + prefix + 'group/member?groupname=' + key
      end

      def paging_path
        prefix = '/'
        unless self.class.belongs_to_relationships.empty?
          prefix = self.class.belongs_to_relationships.inject(prefix) do |prefix_so_far, relationship|
            prefix_so_far.to_s + relationship.to_s + "/" + self.send("#{relationship.to_s}_id").to_s + '/'
          end
        end
        self.class.paging_path(@client, key_value, prefix)
      end

      # Sends a delete request to the JIRA Api and sets the deleted instance
      # variable on the object to true.
      # Not to use singular_path
      def delete
        client.delete(collection_path + "?groupname=#{id}")
        @deleted = true
      end

      # Fetches the attributes for the specified resource from JIRA unless
      # the resource is already expanded and the optional force reload flag
      # is not set
      # JIRA API supports to fetch maximum 50 members at a time, so this method
      # loops to fetch all members in the group
      def fetch(reload = false, query_params = {})
        return if expanded? && !reload
        start_at = 0
        # API MAX
        max_results = 50
        merged_results = nil
        loop do
          additional_params = { startAt: start_at, maxResults: max_results }
          # Should use dedicated URL
          response = client.get(url_with_query_params(paging_path, query_params.merge(additional_params)))
          res = JSON.parse(response.body)
          if merged_results.nil?
            merged_results = res
          else
            merged_results['values'] += res['values']
          end
          break if res['isLast']
          start_at += max_results
        end
        set_attrs(merged_results)
        @expanded = true
      end

      # Group Specific Methods
      #   Group has members which are separated resources in Atlassian.

      # Returns the full path for users of the group
      def self.users_path(client, prefix = '/')
        client.options[:rest_base_path] + prefix + 'group/user'
      end

      def users_path(prefix = "/")
        self.class.users_path(@client, prefix)
      end

      def self.add_member(client, groupname, user_name)
        body_param = { name: user_name }
        client.post(users_path(client) + "?groupname=" + groupname, JSON.dump(body_param))
        true
      end

      def add_member(user_name)
        self.class.add_member(@client, group_name, user_name)
      end

      def self.remove_member(client, groupname, user_name)
        query_param = { groupname: groupname, username: user_name }
        client.delete(users_path(client) + "?" + hash_to_query_string(query_param))
        true
      end

      def remove_member(user_name)
        self.class.remove_member(@client, group_name, user_name)
      end

      def group_name
        name
      rescue
        id
      end
    end
  end
end
