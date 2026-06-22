//import { RiFireFill as icon } from 'react-icons/md';

export default {
  name: 'style',
  // visible title
  title: 'Style',
  type: 'document',
  //icon,
  fields: [
    {
      name: 'name',
      title: 'Style',
      type: 'string',
    },
    {
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: {
        source: 'name',
        maxLength: 100,
      },
    },
    {
      name: 'description',
      title: 'Description',
      type: 'text',
      description: 'Tell us a bit about this label',
    },
    {
        name: 'artists',
        title: 'Artists',
        type: 'array',
        of: [{ type: 'reference', to: [{ type: 'artist' }] }],
      },
    {
        name: 'releases',
        title: 'Releases',
        type: 'array',
        of: [{ type: 'reference', to: [{ type: 'release' }] }],
      },
  ],
};