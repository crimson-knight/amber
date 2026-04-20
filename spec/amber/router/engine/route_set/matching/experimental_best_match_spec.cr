require "../../spec_helper"

private def expect_same_match(router, path : String)
  current = router.find(path)
  experimental = router.find_experimental_best(path)

  experimental.found?.should eq current.found?
  experimental.payload?.should eq current.payload?
  experimental.params.should eq current.params
end

describe "experimental best-match routing" do
  it "matches the current implementation for fixed, variable, glob, and misses" do
    router = build do
      add "/get/domains/mine", :my_domains
      add "/get/domains/:id", :a_domain
      add "/get/posts/:page", :numeric_post, {page: /\d+/}
      add "/get/products/*", :products_slug
      add "/get/products/*/with_name", :products_slug_with_name
      add "/get/books/:id/authors", :book_authors
      add "/get/books/:id/pictures", :book_pictures
    end

    expect_same_match(router, "/get")
    expect_same_match(router, "/get/domains/mine")
    expect_same_match(router, "/get/domains/32")
    expect_same_match(router, "/get/posts/1")
    expect_same_match(router, "/get/posts/foo")
    expect_same_match(router, "/get/products/fancy_hairdoo")
    expect_same_match(router, "/get/products/fancy_hairdoo/with_name")
    expect_same_match(router, "/get/books/3/authors")
    expect_same_match(router, "/get/books/3/pictures")
    expect_same_match(router, "/get/books/3/pages")
  end

  it "preserves insertion-order precedence when multiple routes match" do
    router = build do
      add "/get/domains/:id", :a_domain
      add "/get/domains/mine", :my_domains
    end

    expect_same_match(router, "/get/domains/mine")
    expect_same_match(router, "/get/domains/32")
  end

  it "matches routes with optional segments the same way" do
    router = build do
      add "/get/posts(/:id)", :optional_post
      add "/get/posts/:id/edit", :edit_post
    end

    expect_same_match(router, "/get/posts")
    expect_same_match(router, "/get/posts/7")
    expect_same_match(router, "/get/posts/7/edit")
  end
end
