#Fire Model

Models for Firebase

## Installation

Still working on this.

## Example Usage

Require the library.

    var FM = require('fire-model');
    
Then create the Manager.
    
    var manager = new FM.Manager('https://your-firebase.firebaseIO.com/root');
    
Then create your models.

    var User = FM.Model,extend({
        name: 'User',
        key: 'uid',
        path: 'users',
        data: {
            name: {
                required: true
                validate: FM.validate.string
            },
            email: {
                required: true
                validate: FM.validate.email
            },
            joinedAt: {
                auto: FM.created.timestamp
            },
            updatedAt: {
                auto: FM.every.timestamp
            }
        },
        hasMany: {posts: 'Post'}
        computed: {
            drafts: Fm.computed()
        }
    });
    
    var Post = FM.Model.extend({
        name: 'Post',
        key: 'slug',
        path: 'posts',
        data: {
            title: {
                required: true
                validate: FM.validate.string
            },
            content: {
                default: ''
                validate: FM.validate.string
            },
            joinedAt: {
                auto: FM.created.timestamp
            },
            updatedAt: {
                auto: FM.every.timestamp
            },
            publishedAt: {
                default: 0,
                validate: FM.validate.integer
            }
        },
        hasOne: {author: 'User'},
        computed: {
            FM.computed(isPublished, ['publishedAt'], function(publishedAt){
                return publishedAt != 0;
            })
        }
    })
    
Register the models with the manager.

    manager.register([User, Post])
    
Then we can use our models.
    
    var uid = 'user:1';
    var me = new User(uid);
    me.email('me@mydomain.com')
    me.name('Yours Truly')
    
    user.save(function(error){
        if (error) {
            // handle the error
        } else {
            // whatever you want to do
        }
    });
    
    var slug = 'fern-hill';
    var newPost = new Post(slug);
    newPost.set({
        title: "Fern Hill",
        content: "...And honoured among wagons I was prince of the apple towns...",
        author: me
    })
    
    newPost.save(function(error){
        if (error) {
            // handle the error
        } else {
            // whatever else
        }
    });
    
    newPost.isPublished();  // false
    newPost.published(Date.now());
    newPost.isPublished();  // true
    
    newPost.author() === me;  // true
    
    me.posts()[0] === newPost; // true
    
    newPost.save();

Our data has been written to firebase as follows.

    'root': {
        'users': {
            'user:1': {
                'name': 'Yours Truly',
                'email': 'me@mydomain.com',
                'joinedAt': 123456677,
                'updatedAt': 123456677,
                'posts': {
                    'fern-hill': true
                }
            }
        },
        'posts': {
            'fern-hill': {
                'title': 'Fern Hill',
                'content': '...And honoured among wagons I was prince of the apple towns...',
                'author': 'user:1'
            }
        }
    }

If you have retrieved a model directly from the manager, it is important to close it
when you are done using it.  This tells the manager that it no longer needs to keep track 
of the model so that the garbage collector can retrieve it.  A model should not be used 
after it is closed.

    // done with the post
    newPost.close();
    // done with the user
    me.close();
    
You can retrieve a model from the store using the manager object.

    var user = manager.get('User', 'user:1');
    user.name;  // 'Yours Truly'
    
    
    
    

