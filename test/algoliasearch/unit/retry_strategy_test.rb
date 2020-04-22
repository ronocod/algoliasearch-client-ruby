require 'algoliasearch'
require 'test_helper'

class RetryStrategyTest
  include RetryOutcomeType
  include CallType
  describe 'get tryable hosts' do
    def before_all
      super
      @app_id  = 'app_id'
      @api_key = 'api_key'
      @config  = Algolia::Search::Config.new(app_id: @app_id, api_key: @api_key)
    end

    def test_resets_expired_hosts_according_to_read_type
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com")
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com")

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(READ)
      assert_equal 2, hosts.length
    end

    def test_resets_expired_hosts_according_to_write_type
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com")
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com")

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(WRITE)
      assert_equal 2, hosts.length
    end

    def test_resets_expired_hosts_according_to_read_type_with_timeout
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com")
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false, last_use: Time.new.utc - 1000)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com")

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(READ)
      assert_equal 3, hosts.length
    end

    def test_resets_expired_hosts_according_to_write_type_with_timeout
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com")
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false, last_use: Time.new.utc - 1000)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com")

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(WRITE)
      assert_equal 3, hosts.length
    end

    def test_resets_all_hosts_when_expired_according_to_read_type
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com", up: false)

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(READ)
      assert_equal 3, hosts.length
    end

    def test_resets_all_hosts_when_expired_according_to_write_type
      stateful_hosts = []
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-4.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-5.algolianet.com", up: false)
      stateful_hosts << Algolia::Transport::StatefulHost.new("#{@app_id}-6.algolianet.com", up: false)

      @config.default_hosts = stateful_hosts
      retry_strategy        = Algolia::Transport::RetryStrategy.new(@config)

      hosts = retry_strategy.get_tryable_hosts(WRITE)
      assert_equal 3, hosts.length
    end
  end

  describe 'retry stategy decisions' do
    def before_all
      super
      @app_id         = 'app_id'
      @api_key        = 'api_key'
      @config         = Algolia::Search::Config.new(app_id: @app_id, api_key: @api_key)
      @retry_strategy = Algolia::Transport::RetryStrategy.new(@config)
      @hosts          = @retry_strategy.get_tryable_hosts(READ|WRITE)
    end

    def test_retry_decision_on_300
      decision = @retry_strategy.decide(@hosts.first, http_response_code: 300)
      assert_equal RETRY, decision
    end

    def test_retry_decision_on_500
      retry_strategy = Algolia::Transport::RetryStrategy.new(@config)

      decision = retry_strategy.decide(@hosts.first, http_response_code: 500)
      assert_equal RETRY, decision
    end

    def test_retry_decision_on_timed_out
      retry_strategy = Algolia::Transport::RetryStrategy.new(@config)

      decision = retry_strategy.decide(@hosts.first, is_timed_out: true)
      assert_equal RETRY, decision
    end

    def test_retry_decision_on_400
      retry_strategy = Algolia::Transport::RetryStrategy.new(@config)

      decision = retry_strategy.decide(@hosts.first, http_response_code: 400)
      assert_equal FAILURE, decision
    end

    def test_retry_decision_on_404
      retry_strategy = Algolia::Transport::RetryStrategy.new(@config)

      decision = retry_strategy.decide(@hosts.first, http_response_code: 404)
      assert_equal FAILURE, decision
    end

    def test_retry_decision_on_200
      retry_strategy = Algolia::Transport::RetryStrategy.new(@config)

      decision = retry_strategy.decide(@hosts.first, http_response_code: 200)
      assert_equal SUCCESS, decision
    end
  end
end