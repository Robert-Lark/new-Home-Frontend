//import { RiFireFill as icon } from 'react-icons/md';

export default {
  name: 'label',
  // visible title
  title: 'Label',
  type: 'document',
  //icon,
  fields: [
    {
      name: 'name',
      title: 'Name',
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
      name: 'image',
      title: 'Image',
      type: 'image',
      options: {
        hotspot: true,
      },
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